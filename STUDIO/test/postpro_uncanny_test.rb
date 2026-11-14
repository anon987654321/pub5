# frozen_string_literal: true

require_relative "minitest_helper"
require_relative "../postpro/uncanny"

class TestPostproUncanny < Minitest::Test
  def luma(values)
    Vips::Image.new_from_array(values, scale: 1.0).cast(:float)
  end

  def test_specular_spread_measures_only_variation_inside_highlights
    frame = luma([
      [0.10, 0.20, 0.82, 0.98],
      [0.20, 0.40, 0.82, 0.98]
    ])

    assert_in_delta 0.08, Postpro::Uncanny.specular_spread(frame), 0.0001
  end

  def test_uniform_highlights_have_zero_spread_even_with_a_dark_background
    frame = luma([
      [0.05, 0.15, 0.90, 0.90],
      [0.20, 0.40, 0.90, 0.90]
    ])

    assert_in_delta 0.0, Postpro::Uncanny.specular_spread(frame), 0.0001
  end

  def test_absent_highlights_are_unassessed_not_a_zero_quality_score
    frame = luma([
      [0.05, 0.15, 0.50, 0.79],
      [0.20, 0.40, 0.60, 0.70]
    ])

    assert_nil Postpro::Uncanny.specular_spread(frame)
  end

  def test_reading_formats_unassessed_specular_spread_without_raising
    reading = Postpro::Uncanny::Reading.new(
      texture: 0.1, specular_spread: nil, clipping: 0.0, tonal_range: 0.2
    )

    assert_includes reading.to_s, "specular_spread=n/a"
    assert_nil reading.to_h.fetch(:specular_spread)
  end
end
