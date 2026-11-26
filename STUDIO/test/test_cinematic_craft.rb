# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lora/lora"
require_relative "../replicate/motion"

class TestCinematicCraft < Minitest::Test
  Selfie = Studio::Lora::Selfie
  Craft = Studio::Lora::Craft
  Motion = Studio::ReplicateClient::Motion

  def test_recovered_cinematic_knowledge_has_provenance
    guide = Studio::Lora::Guides.load.fetch("cinematic_craft")
    assert_equal 6, guide.fetch("beats").size
    assert guide.fetch("sources").values.all? { |url| url.start_with?("https://github.com/") }
    guide.fetch("beats").each do |beat|
      assert_includes Craft::LABORATORY, beat.fetch("preset")
      refute_empty beat.fetch("scene")
      refute_empty beat.fetch("motion")
    end
  end

  def test_cinematic_recipe_separates_capture_and_motion
    recipe = Selfie.recipe(1, direction: "film_still")
    refute_empty recipe.fetch("motion")
    refute_includes recipe.fetch("scene"), recipe.fetch("motion")
    assert_equal recipe, Selfie.recipe(1, direction: "film_still")
    assert Selfie.recipe(1).key?("motion")
  end

  def test_original_selfie_composer_retains_distinct_sittings
    recipes = (1..48).map { |number| Selfie.recipe(number, direction: "selfies") }
    assert_equal 48, recipes.map { |recipe| recipe.fetch("scene") }.uniq.size
    recipes.each do |recipe|
      assert_includes Craft::LABORATORY, recipe.fetch("preset")
    end
    assert_raises(ArgumentError) { Selfie.recipe(49, direction: "selfies") }
  end

  def test_native_development_honours_shot_grade
    assert_equal ["golden_age", []], Craft.development(chain: nil, preset: "golden_age")
  end

  def test_frame_sampling_rejects_invalid_count_before_io
    assert_raises(ArgumentError) { Motion.sample_frames("missing", directory: "missing", count: 25) }
    assert_raises(ArgumentError) { Motion.sample_frames("missing", directory: "missing", count: 1) }
  end

  def test_local_frame_sampling_preserves_source
    skip "ffmpeg and ffprobe required" unless %w[ffmpeg ffprobe].all? do |name|
      system(name, "-version", out: File::NULL, err: File::NULL)
    end

    Dir.mktmpdir do |directory|
      clip = File.join(directory, "test.mp4")
      _, _, status = Studio::Subprocess.capture3(
        "ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i",
        "testsrc2=size=160x120:rate=12", "-t", "2", "-c:v", "mpeg4", clip, timeout: 30
      )
      assert status.success?
      sha = Digest::SHA256.file(clip).hexdigest
      output = File.join(directory, "frames")
      receipt = Motion.sample_frames(clip, directory: output, count: 4)
      assert_equal sha, receipt.fetch("source_sha256")
      assert_equal sha, Digest::SHA256.file(clip).hexdigest
      assert_equal 0, receipt.fetch("provider_calls")
      assert_equal "NOT_REVIEWED", receipt.fetch("review")
      assert_equal 4, receipt.fetch("frames").size
      receipt.fetch("frames").each do |frame|
        path = frame.fetch("path")
        assert_equal frame.fetch("sha256"), Digest::SHA256.file(path).hexdigest
        assert_equal 0, File.stat(path).mode & 0o077
      end
      assert_raises(ArgumentError) { Motion.sample_frames(clip, directory: output, count: 4) }
    end
  end
end
