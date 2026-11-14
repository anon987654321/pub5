# frozen_string_literal: true

require "vips"
require_relative "minitest_helper"
require_relative "../postpro/lib/quality_analyzer"
require_relative "../postpro/lib/spectral"

class TestPostproQualityAnalyzer < Minitest::Test
  def report_pixel(red, green, blue)
    image = Vips::Image.new_from_memory(
      [red, green, blue].pack("C*"), 1, 1, 3, :uchar
    ).copy(interpretation: :srgb)
    Postpro::QualityAnalyzer.report_image(image)
  end

  def test_mid_grey_is_decoded_before_linear_luminance_is_measured
    report = report_pixel(128, 128, 128)
    expected = HD.srgb_to_linear(128.0 / 255.0)

    assert_in_delta expected, report.dig(:exposure, :mean_luminance), 1e-6
    refute_in_delta 128.0 / 255.0, report.dig(:exposure, :mean_luminance), 0.05
    assert_includes report.fetch(:sampling), "linear-light"
  end

  def test_primary_red_uses_linear_rec709_weight
    report = report_pixel(255, 0, 0)

    assert_in_delta 0.2126, report.dig(:exposure, :mean_luminance), 1e-6
  end

  def test_primary_green_uses_linear_rec709_weight
    report = report_pixel(0, 255, 0)

    assert_in_delta 0.7152, report.dig(:exposure, :mean_luminance), 1e-6
  end

  def test_primary_blue_uses_linear_rec709_weight
    report = report_pixel(0, 0, 255)

    assert_in_delta 0.0722, report.dig(:exposure, :mean_luminance), 1e-6
  end

  def test_srgb_transfer_functions_round_trip_reference_values
    [0.0, 0.0031308, 0.04045, 0.18, 0.5, 1.0].each do |encoded|
      decoded = HD.srgb_to_linear(encoded)
      assert_in_delta encoded, HD.linear_to_srgb(decoded), 1e-10
    end
  end

  def test_d65_to_d65_spectral_adaptation_is_identity
    matrix = Spectral.adaptation_matrix(Spectral::D65_KELVIN, Spectral::D65_KELVIN)

    3.times do |row|
      3.times do |column|
        expected = row == column ? 1.0 : 0.0
        assert_in_delta expected, matrix[row][column], 1e-9
      end
    end
  end
end
