# frozen_string_literal: true

# The sidechain battery: the Dilla duck is deliberately not a perfect DJ
# sidechain — it breathes from real kick events on a 10 ms staircase, with a
# capped linear release. The proof counts the staircase and the cap.
require_relative "minitest_helper"
require_relative "../dilla/dilla"

class TestDillaSidechain < Minitest::Test
  # The sidechain curve is indexed in milliseconds, so the proofs ride a mix
  # long enough to hold every kick and its capped release.
  def mixer = Dilla::Mixer.new(14.0, {}, nil)

  def kick(at_s, vel)
    Dilla::Event.new(at_s, 0.4, :kick, 36, vel, nil)
  end

  # DILLA rig key imperfect_sidechain: the duck gain is a 10 ms staircase on
  # the real kick envelope — every sample inside one grid block rides the
  # same gain, so the duck stairs in instead of sweeping smoothly.
  def test_the_duck_is_a_ten_millisecond_staircase_on_the_kick_envelope
    m = mixer
    kick_events = [kick(1.0, 1.0)]
    curve = m.sidechain_curve!(kick_events, 0.5, 100)

    assert_equal 0.5, curve[1_000], "amount scales the dip: 1 - 0.5 * 1.0"
    assert_in_delta 1.0 - 0.5 * (1.0 - 60.0 / 160.0), curve[1_060], 0.01,
                    "the release walks the curve back up"
    assert_equal 1.0, curve[1_000 + 160],
                 "after release_ms + 60 the bed is untouched"
    assert_equal 1.0, curve[600], "before the kick nothing is ducked"

    m.bus(:drums).l.fill(1.0)
    m.bus(:drums).r.fill(1.0)
    m.duck!(:drums, curve)
    assert_equal 0.5, m.bus(:drums).l[441_000],
                 "the ms grid maps to samples through duck!'s i / 441"
    assert_equal m.bus(:drums).l[441_000], m.bus(:drums).l[441_440],
                 "samples inside one 10 ms block share a gain"
    refute_equal m.bus(:drums).l[441_440], m.bus(:drums).l[441_441],
                 "the staircase steps at the 441-sample grid, not per sample"
  end

  # The release is capped: a giant configured release_ms cannot park the bed
  # ducked forever — the longest any kick holds it is 260 ms.
  def test_the_release_is_capped_and_zero_amount_never_ducks
    long = mixer.sidechain_curve!([kick(1.0, 1.0)], 0.9, 5_000)
    assert_equal 1.0, long[1_000 + 260],
                 "the release cap ends every duck at 260 ms"

    flat = mixer.sidechain_curve!([kick(0.5, 1.0), kick(1.5, 1.0)], 0.0, 100)
    assert flat.all? { |v| v == 1.0 }, "amount 0 is an untouched bed by contract"
    assert_operator flat.length, :>=, 441 * 2,
                   "the flat curve still spans the full duration"
  end

  # Overlapping kicks take the louder duck (max of envelopes), never stack
  # into a deeper-than-amount dip.
  def test_overlapping_kicks_take_the_louder_duck_not_a_deeper_stacking
    overlap = mixer.sidechain_curve!([kick(1.0, 1.0), kick(1.02, 1.0)], 0.8, 100)

    assert_in_delta 0.2, overlap[1_000], 1e-9,
                 "two overlapping kicks duck to amount once, never twice"
  end
end
