# frozen_string_literal: true

# The loudness battery: the delivery stage measures a K-weighted gated
# estimate and steers hot renders back toward the genre's reference. Both
# halves of that claim get counted arithmetic here, because a master that
# quietly bricks everything into the red is no master.
require_relative "minitest_helper"
require_relative "../dilla/dilla"

class TestDillaLoudness < Minitest::Test
  def mix_of(sine_hz, amplitude, seconds)
    n = (seconds * Dilla::SAMPLE_RATE).to_i
    m = Dilla::Stereo.new(n)
    phase = 0.0
    i = 0
    while i < n
      v = amplitude * Math.sin(2.0 * Math::PI * sine_hz * i / Dilla::SAMPLE_RATE)
      m.l[i] = m.r[i] = v
      i += 1
    end
    m
  end

  # DILLA rig key delivery_lufs: the estimator is K-weighted (high shelf plus
  # 38 Hz high-pass) then gated, and it is measured in dB — halving the
  # amplitude must pull the number down by 6 dB.
  def test_lufs_estimate_drops_six_db_when_amplitude_halves
    loud = Dilla::Master.lufs_estimate(mix_of(440.0, 0.8, 2.0))
    quiet = Dilla::Master.lufs_estimate(mix_of(440.0, 0.4, 2.0))

    assert_in_delta(-6.02, quiet - loud, 0.4,
                    "dB is logarithmic: half the amplitude is minus 6 dB")
    assert_operator quiet, :<, loud, "the quieter mix must measure quieter"
  end

  # The gate keeps the bed: a mix that is mostly inaudible must still read at
  # the level of its audible blocks, inaudible blocks must not drag it down.
  def test_the_gated_estimate_ignores_the_silent_bed
    hot = mix_of(440.0, 0.8, 2.0)
    n = hot.l.length
    bed_start = (n * 0.8).to_i
    i = bed_start
    while i < n
      hot.l[i] = hot.r[i] = 3.0e-6
      i += 1
    end
    clean = mix_of(440.0, 0.8, 2.0)

    hot_lufs = Dilla::Master.lufs_estimate(hot)
    clean_lufs = Dilla::Master.lufs_estimate(clean)
    assert_in_delta 0.8, hot_lufs - clean_lufs, 1.0,
                    "an inaudible bed must not drag the gate's measure down"
  end

  # The steer is a ceiling, not a floor: a hot render is trimmed to the
  # reference, a quiet render comes back exactly as it was.
  def test_steer_to_reference_pulls_a_hot_render_and_leaves_a_quiet_one
    hot = mix_of(440.0, 0.9, 2.0)
    Dilla::Master.saturate!(hot, 1.4)
    before = Dilla::Master.lufs_estimate(hot)
    assert_operator before, :>, -9.5, "the fixture must actually be hot"

    steered = Dilla::Master.steer_to_reference!(hot)
    assert_in_delta -9.5, steered, 0.6,
                    "a hot render is pulled back to the genre reference"
    assert_operator hot.l.map(&:abs).max, :<, 1.0, "the trimmed mix stays inside the rail"

    quiet = mix_of(440.0, 0.2, 2.0)
    quiet_lufs = Dilla::Master.lufs_estimate(quiet)
    assert_operator quiet_lufs, :<=, -9.5, "the fixture must actually be quiet"
    assert_equal Dilla::Master.steer_to_reference!(quiet).round(2), quiet_lufs.round(2),
                 "a quiet render is not inflated back up to the reference"
  end
end
