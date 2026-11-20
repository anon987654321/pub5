# frozen_string_literal: true

require_relative "minitest_helper"
require "tmpdir"
require_relative "../lora/train"

class TestStudioLoraTrainingRunner < Minitest::Test
  def test_preflight_failure_stops_before_any_provider_call
    validator = Object.new
    validator.define_singleton_method(:validate_subject) do |_subject|
      { "training_ready" => false, "blockers" => [{ "detail" => "private training consent is missing" }] }
    end
    client = Object.new
    %i[ensure_private_model! upload_zip train_lora].each do |method|
      client.define_singleton_method(method) do |*|
        flunk "provider must not be called before complete preflight"
      end
    end

    runner = Studio::Lora::Training::Runner.new(client:, validator:, root: Dir.pwd)
    error = assert_raises(Studio::Lora::Training::Error) do
      runner.run(subjects: ["johann"])
    end

    assert_match(/consent is missing/, error.message)
  end

  def test_unknown_and_duplicate_subjects_are_refused
    runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root: Dir.pwd)

    assert_raises(ArgumentError) { runner.send(:normalize_subjects, ["johann", "johann"]) }
    assert_raises(ArgumentError) { runner.send(:normalize_subjects, ["unknown"]) }
  end

  def test_candidate_manifest_is_private_and_explicitly_unapproved
    Dir.mktmpdir("studio-lora-manifest-") do |root|
      subject_directory = File.join(root, "johann")
      cache = File.join(subject_directory, ".cache")
      FileUtils.mkdir_p(cache, mode: 0o700)
      File.chmod(0o700, subject_directory)
      File.chmod(0o700, cache)
      runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root:)
      package = {
        "subject" => "johann", "subject_directory" => subject_directory,
        "model_directory" => "johann", "dataset_sha256" => "a" * 64,
        "trigger_word" => "johann_lora", "steps" => 1600, "lora_rank" => 16
      }

      path = runner.send(:write_candidate_manifest, package, "owner/johann:version123", { "id" => "training123" })
      document = JSON.parse(File.read(path))
      assert_equal "TRAINED_NEEDS_LIKENESS_REVIEW", document.fetch("status")
      assert_equal true, document.fetch("likeness_review_required")
      assert_equal "owner/johann:version123", document.fetch("version")
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  def test_candidate_manifest_preserves_the_previous_private_version
    Dir.mktmpdir("studio-lora-manifest-backup-") do |root|
      subject_directory = File.join(root, "ragnhild")
      cache = File.join(subject_directory, ".cache")
      model_directory = File.join(subject_directory, "weights", "ragnhild")
      FileUtils.mkdir_p(cache, mode: 0o700)
      FileUtils.mkdir_p(model_directory, mode: 0o700)
      [subject_directory, cache, File.join(subject_directory, "weights"), model_directory].each { |path| File.chmod(0o700, path) }
      old_path = File.join(model_directory, "replicate_training.json")
      old = JSON.generate("version" => "owner/ragnhild:oldversion")
      File.write(old_path, old, mode: "w", perm: 0o600)
      runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root:)
      package = {
        "subject" => "ragnhild", "subject_directory" => subject_directory,
        "model_directory" => "ragnhild", "dataset_sha256" => "b" * 64,
        "trigger_word" => "ragnhild", "steps" => 1600, "lora_rank" => 16
      }

      runner.send(:write_candidate_manifest, package, "owner/ragnhild:newversion", { "id" => "training456" })
      backups = Dir.glob(File.join(cache, "previous-training-*.json"))
      assert_equal 1, backups.length
      assert_equal old, File.read(backups.first)
      assert_equal "owner/ragnhild:newversion", JSON.parse(File.read(old_path)).fetch("version")
    end
  end

  def test_all_three_subjects_are_the_default_batch
    assert_equal %w[johann ragnhild merethe], Studio::Lora::Training::SUBJECTS
  end
end
