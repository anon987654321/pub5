# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yaml"
require_relative "minitest_helper"
require_relative "../lora/consent"
require_relative "../lora/validate"

class TestLoraConsent < Minitest::Test
  Consent = Studio::Lora::Consent

  def setup
    @root = Dir.mktmpdir("studio-lora-consent-")
    @subject_dir = File.join(@root, "probe")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def test_complete_private_consent_and_source_evidence_pass
    write_record

    report = Consent.validate(subject: "probe", subject_directory: @subject_dir)

    assert report.fetch("valid"), report.fetch("errors").join("; ")
    assert_empty report.fetch("errors")
    assert_equal File.join(@subject_dir, "consent.yml"), report.fetch("consent_path")
  end

  def test_lora_validator_reports_missing_consent_as_a_training_blocker
    root = File.join(@root, "profiles")
    subject = File.join(root, "probe")
    FileUtils.mkdir_p(subject)
    File.write(File.join(subject, "subject.env.example"), <<~ENV)
      TRIGGER=PROBE
      MODEL=probe
      DESCRIPTOR=synthetic test profile
    ENV

    report = Studio::Lora::Validator.new(root:).validate_subject("probe")

    refute report.fetch("training_ready")
    refute report.fetch("consent_valid")
    assert report.fetch("blockers").any? { |item| item.fetch("id") == "subject_consent" }
  end

  def test_subject_consent_flags_without_a_written_evidence_file_do_not_pass
    write_record(
      subject_consent: {
        "likeness_generation" => true,
        "provider_processing" => true
      }
    )
    report = Consent.validate(subject: "probe", subject_directory: @subject_dir)

    refute report.fetch("valid")
    assert report.fetch("errors").any? { |error| error.include?("subject_consent") }
  end

  def test_missing_record_blocks_without_creating_or_repairing_it
    FileUtils.mkdir_p(@subject_dir, mode: 0o700)
    File.chmod(0o700, @subject_dir)

    error = assert_raises(Consent::Error) do
      Consent.require!(subject: "probe", subject_directory: @subject_dir)
    end

    assert_match(/private consent.yml is missing/, error.message)
    refute File.exist?(File.join(@subject_dir, "consent.yml"))
  end

  def test_subject_and_both_permission_scopes_must_match_explicitly
    write_record(subject: "someone_else")
    report = Consent.validate(subject: "probe", subject_directory: @subject_dir)

    refute report.fetch("valid")
    assert report.fetch("errors").any? { |error| error.include?("subject must match") }
  end

  def test_false_subject_or_source_permissions_block
    write_record(
      subject_consent: { "likeness_generation" => true, "provider_processing" => false },
      source_rights: {
        "generation_use" => true, "provider_processing" => true,
        "evidence" => { "me2_archive" => evidence_entry }
      }
    )
    report = Consent.validate(subject: "probe", subject_directory: @subject_dir)

    refute report.fetch("valid")
    assert report.fetch("errors").any? { |error| error.include?("subject_consent") }
  end

  def test_every_required_source_set_needs_its_own_evidence
    write_record(subject: "wenche", evidence: { "me2_archive" => evidence_entry })
    report = Consent.validate(subject: "wenche", subject_directory: @subject_dir)

    refute report.fetch("valid")
    assert report.fetch("errors").any? { |error| error.include?("website_photographs") }
  end

  def test_evidence_must_be_present_private_and_inside_the_subject_directory
    write_record
    File.chmod(0o644, File.join(@subject_dir, "evidence", "rights-note.txt"))
    report = Consent.validate(subject: "probe", subject_directory: @subject_dir)

    refute report.fetch("valid")
    assert report.fetch("errors").any? { |error| error.include?("stored_at") }
  end

  def test_evidence_symlinks_are_refused
    write_record
    File.delete(File.join(@subject_dir, "evidence", "rights-note.txt"))
    File.write(File.join(@root, "outside.txt"), "not local evidence")
    File.chmod(0o600, File.join(@root, "outside.txt"))
    File.symlink(File.join(@root, "outside.txt"), File.join(@subject_dir, "evidence", "rights-note.txt"))
    report = Consent.validate(subject: "probe", subject_directory: @subject_dir)

    refute report.fetch("valid")
    assert report.fetch("errors").any? { |error| error.include?("stored_at") }
  end

  def test_consent_record_must_be_owner_only
    write_record
    File.chmod(0o644, File.join(@subject_dir, "consent.yml"))
    report = Consent.validate(subject: "probe", subject_directory: @subject_dir)

    refute report.fetch("valid")
    assert report.fetch("errors").any? { |error| error.include?("owner-only") }
  end

  def test_consent_record_with_special_permission_bits_is_not_exactly_private
    write_record
    File.chmod(0o4600, File.join(@subject_dir, "consent.yml"))
    report = Consent.validate(subject: "probe", subject_directory: @subject_dir)

    refute report.fetch("valid")
    assert report.fetch("errors").any? { |error| error.include?("owner-only") }
  end

  def test_source_evidence_must_cover_generation_and_provider_processing
    write_record(evidence: {
      "me2_archive" => evidence_entry("covers" => ["generation_use"])
    })
    report = Consent.validate(subject: "probe", subject_directory: @subject_dir)

    refute report.fetch("valid")
    assert report.fetch("errors").any? { |error| error.include?("provider_processing") }
  end

  def test_subject_specific_source_sets_are_not_inferred_from_public_urls
    assert_equal %w[me2_archive website_photographs],
                 Consent.required_source_sets(subject: "wenche", subject_directory: @subject_dir)
    assert_equal %w[me2_archive],
                 Consent.required_source_sets(subject: "merethe", subject_directory: @subject_dir)
  end

  def test_additional_merethe_images_require_a_separate_rights_record
    additional = File.join(@subject_dir, "sources", "additional")
    FileUtils.mkdir_p(additional, mode: 0o700)
    File.chmod(0o700, File.join(@subject_dir, "sources"))
    File.chmod(0o700, additional)
    File.write(File.join(additional, "portrait.jpg"), "local fixture")
    assert_equal %w[me2_archive additional_images],
                 Consent.required_source_sets(subject: "merethe", subject_directory: @subject_dir)
  end

  private

  def evidence_entry(overrides = {})
    {
      "granted_by" => "recorded test authority",
      "granted_on" => "2026-11-12",
      "covers" => %w[generation_use provider_processing],
      "stored_at" => "evidence/rights-note.txt"
    }.merge(overrides)
  end

  def subject_consent_entry
    evidence_entry(
      "covers" => %w[likeness_generation provider_processing],
      "stored_at" => "evidence/subject-consent.txt"
    )
  end

  def write_record(
    subject: "probe",
    evidence: { "example_source" => evidence_entry },
    subject_consent: { "likeness_generation" => true, "provider_processing" => true, "evidence" => subject_consent_entry },
    source_rights: nil
  )
    FileUtils.mkdir_p(@subject_dir, mode: 0o700)
    File.chmod(0o700, @subject_dir)
    evidence_dir = File.join(@subject_dir, "evidence")
    FileUtils.mkdir_p(evidence_dir, mode: 0o700)
    File.chmod(0o700, evidence_dir)
    evidence_path = File.join(evidence_dir, "rights-note.txt")
    File.write(evidence_path, "synthetic rights evidence\n", mode: "w", perm: 0o600)
    File.chmod(0o600, evidence_path)
    subject_evidence_path = File.join(evidence_dir, "subject-consent.txt")
    File.write(subject_evidence_path, "synthetic subject consent evidence\n", mode: "w", perm: 0o600)
    File.chmod(0o600, subject_evidence_path)
    source_rights ||= {
      "generation_use" => true,
      "provider_processing" => true,
      "evidence" => evidence
    }
    document = {
      "schema" => 1,
      "subject" => subject,
      "subject_consent" => subject_consent,
      "source_rights" => source_rights
    }
    path = File.join(@subject_dir, "consent.yml")
    File.write(path, YAML.dump(document), mode: "w", perm: 0o600)
    File.chmod(0o600, path)
  end
end
