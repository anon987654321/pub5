# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../studio/replicate/lora/merethe/prepare"

class MeretheLoraTest < Minitest::Test
  SUBJECT = Studio::MeretheLora

  def test_archive_inventory_is_complete_and_pinned
    assert_equal 15, SUBJECT::SOURCE_FILES.size
    assert_equal "8e1955ae130592ab7c20ee266c024f061431c67e", SUBJECT::SOURCE_COMMIT
    assert SUBJECT::SOURCE_FILES.values.all? { |sha| sha.match?(/\A[0-9a-f]{40}\z/) }
  end

  def test_only_face_led_non_intimate_archive_frames_are_selected
    assert_equal %w[10.jpg 11.jpg 12.jpg 13.jpg], SUBJECT::CURATED_CAPTIONS.keys
    assert SUBJECT::CURATED_CAPTIONS.values.all? { |caption| caption.include?("MERETHE") }
  end

  def test_git_blob_sha_matches_git_object_format
    assert_equal "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0", SUBJECT.git_blob_sha("hello")
  end

  def test_additional_photos_need_a_valid_image_and_matching_trigger_caption
    Dir.mktmpdir("merethe-lora-test-") do |directory|
      path = File.join(directory, "portrait.jpg")
      File.binwrite(path, "\xFF\xD8\xFF\xD9".b)
      File.write(File.join(directory, "portrait.txt"), "MERETHE, a portrait in daylight\n")

      images, problems = SUBJECT.additional_images(additional_root: directory)
      assert_empty problems
      assert_equal ["portrait.jpg"], images.map { |image| image[:name] }
    end
  end

  def test_missing_captions_block_additional_photos
    Dir.mktmpdir("merethe-lora-test-") do |directory|
      File.binwrite(File.join(directory, "portrait.jpg"), "\xFF\xD8\xFF\xD9".b)

      images, problems = SUBJECT.additional_images(additional_root: directory)
      assert_empty images
      assert_includes problems.join("\n"), "missing same-basename .txt caption"
    end
  end

  def test_no_training_or_provider_upload_is_implemented_in_preparation
    source = File.read(File.expand_path("../../studio/replicate/lora/merethe/prepare.rb", __dir__))
    refute_match(/train_lora|upload_zip|REPLICATE_API_TOKEN/, source)
  end
end
