# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yaml"
require_relative "minitest_helper"
require_relative "../lora/consent"

class TestLoraConsent < Minitest::Test
  Consent = Studio::Lora::Consent

  def setup
    @root = Dir.mktmpdir("studio-lora-consent-")
    @subject_dir = File.join(@root, "probe")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def test_missing_private_consent_blocks_without_creating_a_record
    FileUtils.mkdir_p(@subject_dir, mode: 0o700)
    error = assert_raises(Consent::Error) do
      Consent.require!(subject: "probe", subject_directory: @subject_dir)
    end
    assert_match(/private consent.yml is missing/, error.message)
    refute File.exist?(File.join(@subject_dir, "consent.yml"))
  end

  def test_generation_requires_written_subject_consent_and_source_rights
    write_record
    report = Consent.validate(subject: "probe", subject_directory: @subject_dir, action: :generation)
    assert report.fetch("valid"), report.fetch("errors").join("; ")
  end

  def test_training_requires_separate_training_and_retention_permissions
    write_record
    report = Consent.validate(subject: "probe", subject_directory: @subject_dir, action: :training)
    refute report.fetch("valid")
    assert report.fetch("errors").any? { |error| error.include?("model_training") }
    assert report.fetch("errors").any? { |error| error.include?("model_retention") }

    write_record(training: true)
    report = Consent.validate(subject: "probe", subject_directory: @subject_dir, action: :training)
    assert report.fetch("valid"), report.fetch("errors").join("; ")
  end

  def test_publication_and_distribution_are_separate_permissions
    write_record(training: true)
    refute Consent.validate(subject: "probe", subject_directory: @subject_dir, action: :publication).fetch("valid")
    refute Consent.validate(subject: "probe", subject_directory: @subject_dir, action: :distribution).fetch("valid")

    write_record(training: true, publication: true, distribution: true)
    assert Consent.validate(subject: "probe", subject_directory: @subject_dir, action: :publication).fetch("valid")
    assert Consent.validate(subject: "probe", subject_directory: @subject_dir, action: :distribution).fetch("valid")
  end

  def test_public_or_symlinked_evidence_is_refused
    write_record
    path = File.join(@subject_dir, "evidence", "source-rights.txt")
    File.chmod(0o644, path)
    report = Consent.validate(subject: "probe", subject_directory: @subject_dir)
    refute report.fetch("valid")
    assert report.fetch("errors").any? { |error| error.include?("stored_at") }

    File.chmod(0o600, path)
    File.delete(path)
    outside = File.join(@root, "outside.txt")
    File.write(outside, "outside evidence", mode: "w", perm: 0o600)
    File.symlink(outside, path)
    refute Consent.validate(subject: "probe", subject_directory: @subject_dir).fetch("valid")
  end

  def test_merethe_archive_and_additional_photos_are_distinct_source_sets
    sources = File.join(@subject_dir, "sources")
    additional = File.join(sources, "additional")
    FileUtils.mkdir_p(additional, mode: 0o700)
    File.chmod(0o700, sources)
    File.chmod(0o700, additional)
    File.write(File.join(sources, "01.jpg"), "archive fixture")
    File.write(File.join(additional, "portrait.jpg"), "additional fixture")
    assert_equal %w[me2_archive additional_images],
                 Consent.required_source_sets(subject: "merethe", subject_directory: @subject_dir)
  end

  private

  def write_record(training: false, publication: false, distribution: false)
    FileUtils.mkdir_p(@subject_dir, mode: 0o700)
    evidence = File.join(@subject_dir, "evidence")
    FileUtils.mkdir_p(evidence, mode: 0o700)
    File.chmod(0o700, evidence)

    subject_file = File.join(evidence, "subject-consent.txt")
    source_file = File.join(evidence, "source-rights.txt")
    sources = File.join(@subject_dir, "sources")
    FileUtils.mkdir_p(sources, mode: 0o700)
    File.write(File.join(sources, "photo.jpg"), "synthetic source image")
    if training
      dataset = File.join(@subject_dir, "dataset")
      FileUtils.mkdir_p(dataset, mode: 0o700)
      File.write(File.join(dataset, "training.jpg"), "synthetic training image")
    end
    File.write(subject_file, "synthetic subject authority\n", mode: "w", perm: 0o600)
    File.write(source_file, "synthetic source authority\n", mode: "w", perm: 0o600)
    File.chmod(0o600, subject_file)
    File.chmod(0o600, source_file)

    subject_scopes = %w[likeness_generation provider_processing]
    source_scopes = %w[generation_use provider_processing]
    subject_permissions = {
      "likeness_generation" => true, "provider_processing" => true,
      "model_training" => training, "model_retention" => training,
      "model_publication" => publication, "model_distribution" => distribution
    }
    source_permissions = {
      "generation_use" => true, "provider_processing" => true, "training_use" => training,
      "model_publication" => publication, "model_distribution" => distribution
    }
    if training
      subject_scopes += %w[model_training model_retention]
      source_scopes << "training_use"
    end
    if publication
      subject_scopes << "model_publication"
      source_scopes << "model_publication"
    end
    if distribution
      subject_scopes << "model_distribution"
      source_scopes << "model_distribution"
    end

    document = {
      "schema" => 1,
      "subject" => "probe",
      "subject_consent" => subject_permissions.merge(
        "evidence" => {
          "granted_by" => "synthetic test authority",
          "granted_on" => "2026-11-14",
          "covers" => subject_scopes,
          "stored_at" => "evidence/subject-consent.txt"
        }
      ),
      "source_rights" => source_permissions.merge(
        "evidence" => {
          "subject_sources" => {
            "granted_by" => "synthetic source-rights authority",
            "granted_on" => "2026-11-14",
            "covers" => source_scopes,
            "stored_at" => "evidence/source-rights.txt"
          },
          **(training ? {
            "training_dataset" => {
              "granted_by" => "synthetic dataset authority",
              "granted_on" => "2026-11-14",
              "covers" => source_scopes,
              "stored_at" => "evidence/source-rights.txt"
            }
          } : {})
        }
      )
    }
    path = File.join(@subject_dir, "consent.yml")
    File.write(path, YAML.dump(document), mode: "w", perm: 0o600)
    File.chmod(0o600, path)
  end
end
