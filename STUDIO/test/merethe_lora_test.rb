# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "fileutils"
require_relative "../lora/merethe/prepare"

class TestMeretheLoraPackage < Minitest::Test
  def test_merethe_lora_uses_the_canonical_subject_root
    assert_equal File.expand_path("../lora/merethe", __dir__), Studio::MeretheLora::SUBJECT_ROOT
  end

  def test_historical_source_inventory_is_complete_and_pinned
    assert_equal 15, Studio::MeretheLora::SOURCE_FILES.size
    assert_equal "8e1955ae130592ab7c20ee266c024f061431c67e", Studio::MeretheLora::SOURCE_COMMIT
    assert Studio::MeretheLora::SOURCE_FILES.values.all? { |sha| sha.match?(/\A[0-9a-f]{40}\z/) }
  end

  def test_only_face_led_candidates_enter_the_initial_identity_set
    assert_equal %w[10.jpg 11.jpg 12.jpg 13.jpg], Studio::MeretheLora::CURATED_CAPTIONS.keys
    assert Studio::MeretheLora::CURATED_CAPTIONS.values.all? { |caption| caption.include?("MERETHE") }
  end

  def test_preflight_minimum_matches_trainer_floor_and_target_range
    assert_equal 10, Studio::MeretheLora::MIN_IMAGES
    assert_equal [12, 18], [Studio::MeretheLora::TARGET_MIN_IMAGES, Studio::MeretheLora::MAX_IMAGES]
  end

  def test_trainer_version_is_pinned_not_floating
    assert_equal "ostris/flux-dev-lora-trainer", Studio::MeretheLora::TRAINER
    assert_match(/\A[0-9a-f]{64}\z/, Studio::MeretheLora::TRAINER_VERSION)
  end

  def test_prepared_dataset_and_zip_replace_as_one_recoverable_pair
    Dir.mktmpdir("merethe-publish-") do |root|
      dataset_path = File.join(root, "dataset")
      zip_path = File.join(root, "training.zip")
      staging_root = File.join(root, "stage")
      staged_dataset = File.join(staging_root, "dataset")
      staged_zip = File.join(staging_root, "training.zip")
      FileUtils.mkdir_p(File.join(dataset_path))
      File.write(File.join(dataset_path, "old.txt"), "previous dataset")
      File.write(zip_path, "previous zip")
      FileUtils.mkdir_p(staged_dataset)
      File.write(File.join(staged_dataset, "new.txt"), "new dataset")
      File.write(staged_zip, "new zip")

      result = Studio::MeretheLora.publish_prepared_artifacts!(
        staged_dataset:, staged_zip:, staging_root:, dataset_path:, zip_path:
      )

      assert_equal true, result
      assert_equal "new dataset", File.read(File.join(dataset_path, "new.txt"))
      refute File.exist?(File.join(dataset_path, "old.txt"))
      assert_equal "new zip", File.read(zip_path)
      assert_equal 0o700, File.stat(dataset_path).mode & 0o777
      assert_equal 0o600, File.stat(zip_path).mode & 0o777
    end
  end

  def test_failed_pair_publication_restores_the_previous_dataset_and_zip
    Dir.mktmpdir("merethe-rollback-") do |root|
      dataset_path = File.join(root, "dataset")
      zip_path = File.join(root, "training.zip")
      staging_root = File.join(root, "stage")
      staged_dataset = File.join(staging_root, "dataset")
      staged_zip = File.join(staging_root, "training.zip")
      FileUtils.mkdir_p(dataset_path)
      File.write(File.join(dataset_path, "old.txt"), "previous dataset")
      File.write(zip_path, "previous zip")
      FileUtils.mkdir_p(staged_dataset)
      File.write(File.join(staged_dataset, "new.txt"), "new dataset")
      File.write(staged_zip, "new zip")

      original_rename = File.method(:rename)
      failing_rename = lambda do |source, target|
        raise Errno::EACCES, staged_zip if source == staged_zip

        original_rename.call(source, target)
      end

      File.stub(:rename, failing_rename) do
        assert_raises(Errno::EACCES) do
          Studio::MeretheLora.publish_prepared_artifacts!(
            staged_dataset:, staged_zip:, staging_root:, dataset_path:, zip_path:
          )
        end
      end

      assert_equal "previous dataset", File.read(File.join(dataset_path, "old.txt"))
      refute File.exist?(File.join(dataset_path, "new.txt"))
      assert_equal "previous zip", File.read(zip_path)
    end
  end

  def test_preparation_refuses_before_migration_when_consent_is_missing
    error = Studio::Lora::Consent::Error.new("synthetic missing-consent refusal")
    require_consent = lambda do |**_arguments|
      raise error
    end
    migration = -> { flunk "legacy data must not be moved before consent" }

    report = nil
    Studio::Lora::Consent.stub(:required_source_sets, ["me2_archive"]) do
      Studio::Lora::Consent.stub(:require!, require_consent) do
        Studio::MeretheLora.stub(:migrate_legacy_local_data!, migration) do
          report = Studio::MeretheLora.prepare!
        end
      end
    end

    assert_equal "BLOCKED_CONSENT", report.fetch("status")
    assert_equal false, report.fetch("training_started")
    assert_equal false, report.fetch("provider_upload_started")
    assert_match(/synthetic missing-consent refusal/, report.fetch("error"))
  end

  def test_preparation_is_local_only
    source = File.read(File.expand_path("../lora/merethe/prepare.rb", __dir__))
    refute_match(/train_lora|upload_zip|REPLICATE_API_TOKEN/, source)
  end
end
