# frozen_string_literal: true

# The twelve-bit battery: the SP/MPC-era grit in dilla is a quantizer, and
# a quantizer's defects are inaudible until the grid is counted, so the
# proof counts the grid. Every method a capability promotion cites under
# Studio::AnalogCapabilities must live in a test like this one.
require_relative "minitest_helper"
require_relative "../dilla/dilla"

class TestDillaCrush < Minitest::Test
  def quantize(samples, bits)
    dk = Dilla::DrumKit.new({})
    dk.crush!(samples.dup, bits)
  end

  # DILLA rig key mpc_twelve_bit: the hit and sample-flip paths crush to
  # levels = 2**(bits-1) steps, so every value lands on the 12-bit grid.
  def test_mpc_twelve_bit_quantizes_to_a_step_grid
    sine = (0..3_999).map { |i| 0.8 * Math.sin(2.0 * Math::PI * 220.0 * i / 44_100.0) }
    out = quantize(sine, 12)

    assert_equal sine.length, out.length
    levels = (2.0**11)
    off_grid = out.count do |v|
      snapped = (v * levels).round / levels
      (snapped - v).abs > 1e-9
    end
    assert_equal 0, off_grid, "every crushed sample must sit exactly on the 12-bit grid"
  end

  # The crush must lose real precision but stay inside one step of truth —
  # a quantizer that moved values a whole step is bit-shifting, not grit.
  def test_the_crush_stays_within_one_level_step_of_the_input
    ramp = (0..2_099).map { |i| -1.0 + i * (2.0 / 2_100.0) }
    out = quantize(ramp, 12)

    step = 1.0 / (2.0**11)
    worst = ramp.zip(out).map { |a, b| (b - a).abs }.max
    assert_operator worst, :<=, step + 1e-9,
                   "a quantizer's worst error is one level step, not a whole step plus"
    assert_operator worst, :>, 1e-6,
                   "the twelve-bit grid must actually bite the samples"
  end

  # At full word depth the path is a documented no-op: a 16-bit-plus chain
  # carries no crush stage at all.
  def test_sixteen_bits_and_up_pass_the_buffer_through_untouched
    sines = (0..499).map { |i| 0.5 * Math.sin(i * 0.05) }

    assert(quantize(sines, 16).zip(sines).sum { |a, b| (a - b).abs } < 1e-12)
    assert(quantize(sines, 21).zip(sines).sum { |a, b| (a - b).abs } < 1e-12)
  end
end
