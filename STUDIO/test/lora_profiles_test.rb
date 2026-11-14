# frozen_string_literal: true

require_relative "minitest_helper"
require "tmpdir"
require "fileutils"
require "yaml"
require_relative "../lora/validate"

class TestStudioLoraValidator < Minitest::Test
  def test_repository_profiles_are_discovered_without_provider_calls
    report = Studio::Lora::Validator.new.validate_all
    names = report.fetch("subjects").map { |item| item.fetch("subject") }

    %w[johann merethe ragnhild].each { |name| assert_includes names, name }
    assert_equal 0, report.fetch("provider_calls")
    assert_equal true, report.fetch("read_only")
    assert report.fetch("subjects").all? { |item| item.fetch("state") == "PASS" }
    refute report.fetch("subjects").all? { |item| item.fetch("training_ready") }
  end

  def test_complete_private_training_plan_is_ready_for_operator_review
    with_subject do |root, directory|
      write_descriptor(directory)
      dataset = File.join(directory, "dataset")
      FileUtils.mkdir_p(dataset)
      10.times do |index|
        File.write(File.join(dataset, "photo-#{index}.jpg"), "image")
        File.write(File.join(dataset, "photo-#{index}.txt"), "SAMPLE portrait #{index}")
      end
      write_training_plan(directory, dataset: "dataset")
      write_valid_consent(directory)

      report = Studio::Lora::Validator.new(root:).validate_subject("sample")

      assert_equal "PASS", report.fetch("state")
      assert_equal true, report.fetch("training_ready")
      assert_equal "READY_FOR_OPERATOR_REVIEW", report.fetch("training_readiness")
      assert report.fetch("checks").any? { |item| item["id"] == "dataset_integrity" }
    end
  end

  def test_blank_dataset_path_is_blocked_not_misreported_as_ready
    with_subject do |root, directory|
      write_descriptor(directory)
      write_training_plan(directory, dataset: "")

      report = Studio::Lora::Validator.new(root:).validate_subject("sample")

      assert_equal "PASS", report.fetch("state")
      refute report.fetch("training_ready")
      assert_includes report.fetch("blockers").map { |item| item["id"] }, "dataset_path"
    end
  end

  def test_training_manifest_lookup_refuses_symlinked_weights
    outside = Dir.mktmpdir("lora-outside-")
    begin
      with_subject do |root, directory|
        write_descriptor(directory)
        FileUtils.mkdir_p(File.join(outside, "sample"))
        File.write(File.join(outside, "sample", "replicate_training.json"),
                   JSON.generate("version" => "owner/model:" + ("a" * 64)))
        File.symlink(outside, File.join(directory, "weights"))
        write_training_plan(directory, dataset: "")

        report = Studio::Lora::Validator.new(root:).validate_subject("sample")

        assert_equal "FAIL", report.fetch("state")
        assert_includes report.fetch("blockers").map { |item| item["id"] }, "replicate_manifest_path"
      end
    ensure
      FileUtils.remove_entry(outside) if File.directory?(outside)
    end
  end

  def test_dataset_cannot_escape_the_private_subject_directory
    with_subject do |root, directory|
      write_descriptor(directory)
      write_training_plan(directory, dataset: "../shared-dataset")

      report = Studio::Lora::Validator.new(root:).validate_subject("sample")

      assert_equal "FAIL", report.fetch("state")
      assert_includes report.fetch("blockers").map { |item| item["id"] }, "dataset_path_scope"
    end
  end

  def test_trigger_must_match_and_automatic_publication_must_be_disabled
    with_subject do |root, directory|
      write_descriptor(directory)
      write_training_plan(directory, dataset: "", trigger: "OTHER", push_to_hub: true)

      report = Studio::Lora::Validator.new(root:).validate_subject("sample")
      blocker_ids = report.fetch("blockers").map { |item| item["id"] }

      assert_equal "FAIL", report.fetch("state")
      assert_includes blocker_ids, "trainer_trigger_matches_subject"
      assert_includes blocker_ids, "private_training_output"
    end
  end

  def test_subject_descriptor_rejects_secret_fields_and_duplicate_keys
    with_subject do |root, directory|
      File.write(File.join(directory, "subject.env"), <<~ENV)
        TRIGGER=SAMPLE
        TRIGGER=OTHER
        MODEL=sample
        DESCRIPTOR=ordinary portrait subject
        REPLICATE_API_TOKEN=must-not-live-here
      ENV
      write_training_plan(directory, dataset: "")

      report = Studio::Lora::Validator.new(root:).validate_subject("sample")
      blocker_ids = report.fetch("blockers").map { |item| item["id"] }

      assert_equal "FAIL", report.fetch("state")
      assert_includes blocker_ids, "duplicate_subject_field"
      assert_includes blocker_ids, "credential_in_subject_descriptor"
    end
  end

  private

  def with_subject
    Dir.mktmpdir("studio-lora-validator-") do |root|
      directory = File.join(root, "sample")
      FileUtils.mkdir_p(directory)
      yield root, directory
    end
  end

  def write_valid_consent(directory)
    evidence = File.join(directory, "evidence")
    FileUtils.mkdir_p(evidence, mode: 0o700)
    File.chmod(0o700, evidence)
    subject_file = File.join(evidence, "subject-consent.txt")
    source_file = File.join(evidence, "dataset-rights.txt")
    File.write(subject_file, "synthetic subject authority\n", mode: "w", perm: 0o600)
    File.write(source_file, "synthetic dataset authority\n", mode: "w", perm: 0o600)
    File.chmod(0o600, subject_file)
    File.chmod(0o600, source_file)
    record = {
      "schema" => 1,
      "subject" => "sample",
      "subject_consent" => {
        "likeness_generation" => true, "provider_processing" => true,
        "model_training" => true, "model_retention" => true,
        "evidence" => {
          "granted_by" => "synthetic test authority",
          "granted_on" => "2026-11-14",
          "covers" => %w[likeness_generation provider_processing model_training model_retention],
          "stored_at" => "evidence/subject-consent.txt"
        }
      },
      "source_rights" => {
        "generation_use" => true, "provider_processing" => true, "training_use" => true,
        "evidence" => {
          "training_dataset" => {
            "granted_by" => "synthetic dataset authority",
            "granted_on" => "2026-11-14",
            "covers" => %w[generation_use provider_processing training_use],
            "stored_at" => "evidence/dataset-rights.txt"
          }
        }
      }
    }
    path = File.join(directory, "consent.yml")
    File.write(path, YAML.dump(record), mode: "w", perm: 0o600)
    File.chmod(0o600, path)
  end

  def write_descriptor(directory)
    File.write(File.join(directory, "subject.env"), <<~ENV)
      TRIGGER=SAMPLE
      MODEL=sample
      DESCRIPTOR=ordinary portrait subject
    ENV
  end

  def write_training_plan(directory, dataset:, trigger: "SAMPLE", push_to_hub: false)
    document = {
      "job" => "extension",
      "config" => {
        "name" => "sample",
        "process" => [
          {
            "type" => "sd_trainer",
            "trigger_word" => trigger,
            "network" => { "type" => "lora", "linear" => 16 },
            "save" => { "push_to_hub" => push_to_hub },
            "train" => { "steps" => 1_000 },
            "datasets" => [{ "folder_path" => dataset }]
          }
        ]
      }
    }
    File.write(File.join(directory, "train.yaml"), YAML.dump(document))
  end
end
