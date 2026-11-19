# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "yaml"
require_relative "minitest_helper"
require_relative "../lora/consent"

class TestLoraConsent < Minitest::Test
  Consent = Studio::Lora::Consent
  REPOSITORY_ROOT = File.expand_path("../..", __dir__)

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

  def test_subject_media_and_permission_records_are_ignored_for_new_files
    paths = %w[
      STUDIO/lora/probe/sources/photo.jpg
      STUDIO/lora/probe/references/reference.jpg
      STUDIO/lora/probe/subject.env
      STUDIO/lora/probe/consent.yml
      STUDIO/lora/probe/evidence/permission.pdf
      STUDIO/lora/probe/weights/adapter.safetensors
      STUDIO/lora/probe/out/render.jpg
      STUDIO/lora/probe/retouched/photo.jpg
      STUDIO/lora/probe/dataset/photo.jpg
      STUDIO/lora/probe/dataset_first/photo.jpg
      STUDIO/lora/probe/ledger.jsonl
    ]
    output, error, status = Open3.capture3(
      "git", "check-ignore", "--no-index", "--stdin",
      chdir: REPOSITORY_ROOT, stdin_data: "#{paths.join("\n")}\n"
    )

    assert status.success?, "git check-ignore failed: #{error}"
    assert_equal paths.sort, output.lines.map(&:strip).sort,
                 "new subject material must stay local by default"
  end

  def test_source_photographs_must_be_private_and_singly_linked
    write_record
    references = File.join(@subject_dir, "references")
    FileUtils.mkdir_p(references, mode: 0o700)
    File.chmod(0o700, references)
    image = File.join(references, "portrait.jpg")
    File.write(image, "synthetic reference", mode: "w", perm: 0o644)

    error = assert_raises(Consent::Error) do
      Consent.required_source_sets(subject: "probe", subject_directory: @subject_dir)
    end
    assert_match(/owner-only \(0600\)/, error.message)

    File.chmod(0o600, image)
    assert_equal %w[reference_photographs subject_sources],
                 Consent.required_source_sets(subject: "probe", subject_directory: @subject_dir)

    linked = File.join(references, "second-name.jpg")
    File.link(image, linked)
    error = assert_raises(Consent::Error) do
      Consent.required_source_sets(subject: "probe", subject_directory: @subject_dir)
    end
    assert_match(/singly-linked/, error.message)
  end

  def test_merethe_archive_and_additional_photos_are_distinct_source_sets
    sources = File.join(@subject_dir, "sources")
    additional = File.join(sources, "additional")
    FileUtils.mkdir_p(additional, mode: 0o700)
    File.chmod(0o700, sources)
    File.chmod(0o700, additional)
    File.write(File.join(sources, "01.jpg"), "archive fixture", mode: "w", perm: 0o600)
    File.write(File.join(additional, "portrait.jpg"), "additional fixture", mode: "w", perm: 0o600)
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
    dataset_file = File.join(evidence, "dataset-rights.txt")
    sources = File.join(@subject_dir, "sources")
    FileUtils.mkdir_p(sources, mode: 0o700)
    File.write(File.join(sources, "photo.jpg"), "synthetic source image", mode: "w", perm: 0o600)
    if training
      dataset = File.join(@subject_dir, "dataset")
      FileUtils.mkdir_p(dataset, mode: 0o700)
      File.write(File.join(dataset, "training.jpg"), "synthetic training image")
    end
    File.write(subject_file, "synthetic subject authority\n", mode: "w", perm: 0o600)
    File.write(source_file, "synthetic source authority\n", mode: "w", perm: 0o600)
    File.write(dataset_file, "synthetic dataset authority\n", mode: "w", perm: 0o600)
    File.chmod(0o600, subject_file)
    File.chmod(0o600, source_file)
    File.chmod(0o600, dataset_file)

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
          "stored_at" => "evidence/subject-consent.txt",
        }
      ),
      "source_rights" => source_permissions.merge(
        "evidence" => {
          "subject_sources" => {
            "granted_by" => "synthetic source-rights authority",
            "granted_on" => "2026-11-14",
            "covers" => source_scopes.dup,
            "stored_at" => "evidence/source-rights.txt",
          },
          **(training ? {
            "training_dataset" => {
              "granted_by" => "synthetic dataset authority",
              "granted_on" => "2026-11-14",
              "covers" => source_scopes.dup,
              "stored_at" => "evidence/dataset-rights.txt",
            },
          } : {}),
        }
      )
    }
    path = File.join(@subject_dir, "consent.yml")
    File.write(path, YAML.dump(document), mode: "w", perm: 0o600)
    File.chmod(0o600, path)
  end
end
