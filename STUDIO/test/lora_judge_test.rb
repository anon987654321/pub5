# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "yaml"
require_relative "minitest_helper"
require_relative "../lora/judge"

class TestStudioLoraJudge < Minitest::Test
  Judge = Studio::Lora::Judge

  def setup
    @root = Dir.mktmpdir("studio-lora-judge-")
    @references = File.join(@root, "references")
    FileUtils.mkdir_p(@references, mode: 0o700)
    5.times { |index| File.write(File.join(@references, "reference-#{index + 1}.jpg"), "fixture") }
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def reading(texture: 0.12, tonal_range: 0.24, clipping: 0.0, specular_spread: 0.10)
    Postpro::Uncanny::Reading.new(texture:, tonal_range:, clipping:, specular_spread:)
  end

  def test_thresholds_require_all_metrics_and_physical_finite_values
    valid = {
      "texture" => 0.1,
      "tonal_range" => 0.2,
      "clipping" => 0.0,
      "specular_spread" => 0.1
    }
    assert_equal valid, Judge.validate_thresholds!(valid)

    assert_raises(Judge::ThresholdError) { Judge.validate_thresholds!(valid.reject { |key, _| key == "texture" }) }
    assert_raises(Judge::ThresholdError) { Judge.validate_thresholds!(valid.merge("texture" => "0.1")) }
    assert_raises(Judge::ThresholdError) { Judge.validate_thresholds!(valid.merge("clipping" => Float::NAN)) }
    assert_raises(Judge::ThresholdError) { Judge.validate_thresholds!(valid.merge("tonal_range" => 0.9)) }
    assert_raises(Judge::ThresholdError) { Judge.validate_thresholds!(valid.merge("extra" => 0.1)) }
  end

  def test_faults_are_reported_for_every_breached_metric
    limits = {
      "texture" => 0.1,
      "tonal_range" => 0.2,
      "clipping" => 1.0,
      "specular_spread" => 0.1
    }
    faults = Judge.faults_for(
      reading(texture: 0.05, tonal_range: 0.1, clipping: 2.0, specular_spread: 0.2),
      limits
    )
    assert_equal %w[texture tonal_range clipping specular_spread], faults.map { |fault| fault.fetch(:metric) }
  end

  def test_candidate_with_non_finite_reading_fails_closed
    limits = {
      "texture" => 0.1,
      "tonal_range" => 0.2,
      "clipping" => 1.0,
      "specular_spread" => 0.1
    }
    assert_raises(Judge::CalibrationError) do
      Judge.faults_for(reading(texture: Float::NAN), limits)
    end
  end

  def test_frames_skip_symlinks_and_contact_sheet_sidecars
    contact = File.join(@references, "postpro_contact.jpg")
    File.write(contact, "fixture")
    File.write("#{contact}.json", JSON.generate("schema" => "postpro.contact.v1"))

    legacy = File.join(@references, "contact_sheet-old.jpg")
    File.write(legacy, "fixture")

    outside = File.join(@root, "outside.jpg")
    File.write(outside, "fixture")
    File.symlink(outside, File.join(@references, "linked.jpg"))

    frames = Judge.frames_in(@references, nil)
    names = frames.map { |path| path.basename.to_s }
    assert_equal (1..5).map { |index| "reference-#{index}.jpg" }, names
  end

  def test_calibration_requires_five_regular_reference_images
    2.times { |index| File.write(File.join(@references, "reference-#{index + 1}.jpg"), "fixture") }
    FileUtils.rm_f(File.join(@references, "reference-5.jpg"))

    assert_raises(Judge::CalibrationError) do
      Judge.calibrate(@references, nil)
    end
  end

  def test_calibration_emits_aggregate_yaml_without_paths_or_file_mutation
    original = File.read(Judge::THRESHOLDS_FILE)
    samples = [
      reading(texture: 0.10, tonal_range: 0.21, clipping: 0.1, specular_spread: 0.10),
      reading(texture: 0.12, tonal_range: 0.23, clipping: 0.2, specular_spread: 0.11),
      reading(texture: 0.14, tonal_range: 0.25, clipping: 0.3, specular_spread: 0.12),
      reading(texture: 0.16, tonal_range: 0.27, clipping: 0.4, specular_spread: 0.13),
      reading(texture: 0.18, tonal_range: 0.29, clipping: 0.5, specular_spread: 0.14)
    ]

    output, = capture_io do
      Postpro::Uncanny.stub(:read, ->(_path) { samples.shift }) do
        Judge.calibrate(@references, nil)
      end
    end

    document = YAML.safe_load(output)
    assert_equal 5, document.dig("calibration", "image_count")
    assert_equal 0.1, document.dig("thresholds", "texture")
    assert_equal 0.5, document.dig("thresholds", "clipping")
    refute_includes output, @references
    assert_equal original, File.read(Judge::THRESHOLDS_FILE)
  end

  def test_explicit_calibration_file_is_new_private_and_never_overwritten
    samples = Array.new(5) { reading }
    target = File.join(@root, "thresholds.private.yml")
    Postpro::Uncanny.stub(:read, ->(_path) { samples.shift }) do
      Judge.calibrate(@references, nil, output: target)
    end

    assert_equal 0o600, File.stat(target).mode & 0o777
    existing = File.read(target)
    assert_raises(Judge::CalibrationError) { Judge.write_calibration(target, "replace") }
    assert_equal existing, File.read(target)
    refute_includes existing, @references
  end

  def test_private_threshold_override_rejects_checkout_and_symlink_paths
    private_file = File.join(@root, "private-thresholds.yml")
    File.write(private_file, "thresholds: {}\n")
    ENV.stub("STUDIO_LORA_THRESHOLDS", private_file) do
      assert_equal private_file, Judge.thresholds_path
    end

    inside = File.join(Studio::OutputPaths::REPOSITORY_ROOT, "STUDIO", "lora", "missing-thresholds.yml")
    ENV.stub("STUDIO_LORA_THRESHOLDS", inside) do
      assert_raises(Judge::ThresholdError) { Judge.thresholds_path }
    end

    link = File.join(@root, "linked-thresholds.yml")
    File.symlink(private_file, link)
    ENV.stub("STUDIO_LORA_THRESHOLDS", link) do
      assert_raises(Judge::ThresholdError) { Judge.thresholds_path }
    end
  end

  def test_calibration_refuses_reference_or_output_paths_inside_checkout
    repo = Studio::OutputPaths::REPOSITORY_ROOT
    assert_raises(Judge::CalibrationError) { Judge.reference_directory!(repo) }
    assert_raises(Judge::CalibrationError) do
      Judge.write_calibration(File.join(repo, ".judge-test.yml"), "thresholds: {}")
    end
  end
end
