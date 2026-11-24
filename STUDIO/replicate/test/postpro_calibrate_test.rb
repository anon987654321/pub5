# frozen_string_literal: true

require_relative "minitest_helper"
require "tmpdir"

begin
  require_relative "../../postpro/calibrate"
rescue LoadError => error
  # calibrate.rb pulls in vips through uncanny.rb; a machine without the gem
  # still runs the rest of the suite.
  warn "skipping postpro calibration tests: #{error.message}"
  return
end

# The calibration gate turns "it looks like film" from an assertion into a
# measurement: a grade must sit inside the envelope of a real reference scan,
# and the verdict logic is pure so it can be pinned without images.
class TestPostproCalibrate < Minitest::Test
  Calibrate = Postpro::Calibrate

  Reference = {
    "texture" => 1.20, "specular_spread" => 0.30,
    "clipping" => 0.5, "tonal_range" => 0.30,
  }.freeze

  def test_inside_envelope_passes
    graded = { "texture" => 1.15, "specular_spread" => 0.32, "clipping" => 0.9, "tonal_range" => 0.29 }
    verdict = Calibrate.verdict(Reference, graded)
    assert_equal "WITHIN_ENVELOPE", verdict.fetch("state")
    assert_empty verdict.fetch("outside_axes")
    assert_in_delta 0.4, verdict.dig("deltas", "clipping"), 1.0e-6
  end

  def test_waxy_skin_fails_the_texture_axis
    graded = { "texture" => 0.60, "specular_spread" => 0.30, "clipping" => 0.5, "tonal_range" => 0.30 }
    verdict = Calibrate.verdict(Reference, graded)
    assert_equal "OUTSIDE_ENVELOPE", verdict.fetch("state")
    assert_equal %w[texture], verdict.fetch("outside_axes")
  end

  def test_blown_highlights_fail_absolute_not_relative
    graded = { "texture" => 1.20, "specular_spread" => 0.30, "clipping" => 2.0, "tonal_range" => 0.30 }
    verdict = Calibrate.verdict(Reference, graded)
    assert_equal %w[clipping], verdict.fetch("outside_axes")
  end

  def test_missing_specular_skips_the_axis_instead_of_inventing_one
    graded = { "texture" => 1.20, "specular_spread" => nil, "clipping" => 0.5, "tonal_range" => 0.30 }
    verdict = Calibrate.verdict(Reference, graded)
    assert_equal "WITHIN_ENVELOPE", verdict.fetch("state")
    refute verdict.fetch("deltas").key?("specular_spread")
  end

  def test_pairing_is_by_basename_and_reports_unmatched
    Dir.mktmpdir do |root|
      reference = File.join(root, "reference")
      graded = File.join(root, "graded")
      [reference, graded].each { |dir| Dir.mkdir(dir, 0o700) }
      write_private(reference, "a.jpg")
      write_private(reference, "b.jpg")
      write_private(graded, "a.jpg")
      write_private(graded, "c.jpg")

      pairing = Calibrate.pair(reference, graded)
      assert_equal 1, pairing.fetch("pairs").length
      assert_equal %w[b.jpg], pairing.fetch("unmatched_reference")
      assert_equal %w[c.jpg], pairing.fetch("unmatched_graded")
    end
  end

  def test_missing_reference_directory_is_an_honest_block
    Dir.mktmpdir do |root|
      error = assert_raises(Calibrate::Error) { Calibrate.pair(File.join(root, "nope"), root) }
      assert_match(/reference directory/, error.message)
    end
  end

  def test_no_directories_reports_not_calibrated
    receipt = Calibrate.not_calibrated("no reference or graded directory supplied")
    assert_equal "NOT_CALIBRATED", receipt.fetch("state")
    assert_equal 0, receipt.fetch("provider_calls")
  end

  private

  def write_private(directory, name)
    path = File.join(directory, name)
    File.binwrite(path, "bytes-#{name}")
    File.chmod(0o600, path)
  end
end
