# frozen_string_literal: true

require "json"
require_relative "minitest_helper"

Object.const_set(:CAMERA_PROFILES, {
  "canon" => {
    "canon eos 100d" => { "color_matrix" => [1] * 9, "source" => "fixture" },
    "canon eos 1200d" => { "color_matrix" => [2] * 9, "source" => "fixture" }
  },
  "fujifilm" => {
    "fujifilm x100s" => { "color_matrix" => [3] * 9, "source" => "fixture" }
  }
}) unless Object.const_defined?(:CAMERA_PROFILES)

require_relative "../postpro/lib/hd"

class TestPostproCameraProfiles < Minitest::Test
  class ExifImage
    def initialize(make:, model:)
      @values = { "exif-ifd0-Make" => make, "exif-ifd0-Model" => model }
    end

    def get(key) = @values[key]
  end

  def test_combined_make_and_model_match_is_exact
    profile = get_camera_profile(ExifImage.new(make: "Canon Inc.", model: "EOS 100D"))
    assert_equal [1] * 9, profile.fetch("color_matrix")
  end

  def test_full_model_matches_when_make_is_missing
    profile = get_camera_profile(ExifImage.new(make: "", model: "Canon EOS 1200D"))
    assert_equal [2] * 9, profile.fetch("color_matrix")
  end

  def test_unknown_model_never_borrows_first_manufacturer_profile
    assert_nil get_camera_profile(ExifImage.new(make: "Canon Inc.", model: "EOS R99"))
  end

  def test_missing_metadata_is_a_no_op
    assert_nil get_camera_profile(ExifImage.new(make: "Canon", model: ""))
  end

  def test_camera_catalogue_has_121_bodies_with_finite_matrices
    profiles = JSON.parse(File.read(File.expand_path("../postpro/camera_profiles.json", __dir__)))
    assert_equal 121, profiles.values.sum(&:size)
    assert profiles.values.all? do |models|
      models.values.all? do |entry|
        matrix = entry.fetch("color_matrix")
        matrix.length == 9 && matrix.all? { |value| value.is_a?(Numeric) && value.finite? }
      end
    end
  end

  def test_untyped_dcp_matrix_is_not_applied_to_rendered_srgb
    image = Object.new
    profile = {
      "color_matrix" => [0.7, -0.16, -0.04, -0.36, 1.07, 0.33, -0.03, 0.11, 0.65],
      "source" => "VSCO DCP, Kodak Portra 400 2C profile for this body"
    }

    refute camera_profile_applicable?(profile)
    assert_same image, apply_camera_profile(image, profile)
  end

  def test_only_finite_three_by_three_linear_srgb_contract_is_applicable
    profile = {
      "matrix_contract" => "linear_srgb_to_linear_srgb",
      "color_matrix" => [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
    }

    assert camera_profile_applicable?(profile)
    refute camera_profile_applicable?(profile.merge("matrix_contract" => "xyz_to_camera_native"))
    refute camera_profile_applicable?(profile.merge("color_matrix" => [Float::NAN] + [0.0] * 8))
    refute camera_profile_applicable?(profile.merge("color_matrix" => [1.0] * 8))
  end
end
