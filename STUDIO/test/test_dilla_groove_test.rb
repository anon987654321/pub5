# frozen_string_literal: true

# The pocket battery: the performance engine's micro-timing is the reason a
# Dilla render leans — kicks late, snares early, hats under, and MPC swing
# sliding the off-16th toward the triplet. These are counted, not felt.
require_relative "minitest_helper"
require_relative "../dilla/dilla"

class TestDillaGroove < Minitest::Test
  def groove(swing: 54.0, profile: {}, performer: {})
    Dilla::Groove.new(bpm: 90, swing: swing, profile: profile, performer: performer)
  end

  # DILLA rig key hit_microtiming: the lane nudges are the documented pocket —
  # the kick leans late, the snare leans early, hats and ghosts sit around it.
  # The sequencer drives nudge with string lanes and converts to a symbol only
  # at the Event, so the strings are the real contract.
  def test_the_pocket_nudges_kick_late_and_snare_early
    g = groove

    assert_operator g.nudge("kick"), :>, 0.0, "the kick leans late"
    assert_operator g.nudge("snare"), :<, 0.0, "the snare leans early"
    assert_operator g.nudge("hat"), :<, 0.0, "hats sit under the pocket"
    assert_operator g.nudge("ghost"), :>, 0.0, "ghosts lean late"
    assert_operator g.nudge("ghost").abs, :<, g.nudge("kick").abs,
                 "ghosts lean less than the kick"
    assert_operator g.nudge("ride"), :==, 0.0, "an unprofiled lane stays on the grid"
  end

  # The profile owns the pocket, the performer scales it: an override is
  # respected and a positive kick_bias leans the kick further late.
  def test_profile_overrides_and_performer_bias_scale_the_nudge
    g = groove(profile: { "nudge" => { "kick" => 5.0 } }, performer: { "kick_bias" => 1.0 })

    assert_in_delta 10.0, g.nudge("kick"), 1e-9,
                    "5.0 * (1 + 1.0): the profile's own nudge, scaled by the performer"
    assert_operator groove.nudge(:kick), :>, groove(performer: { "kick_bias" => 0.5 }).nudge(:kick) - 1e-9
  end

  # DILLA swing is MPC swing: 50 percent is the straight grid, 66 percent is
  # the triplet slide, everything between is monotone, and past 66 it clamps.
  def test_mpc_swing_slides_the_off_sixteenth_to_the_triplet
    straight = groove(swing: 50.0)
    triplet = groove(swing: 66.0)
    pocket = groove(swing: 54.0)

    assert_equal 0.0, straight.swing_delay_s, "50 percent does not move the grid"
    assert_operator pocket.swing_delay_s, :>, 0.0,
                    "54 percent leans off the grid"
    assert_operator pocket.swing_delay_s, :<, triplet.swing_delay_s,
                    "the document: 54 is the pocket between straight and triplet"
    assert_in_delta((2.0 / 3.0 - 0.5) * triplet.eighth_s, triplet.swing_delay_s, 1e-9,
                    "66 percent is the triplet position")
    assert_operator groove(swing: 90.0).swing_delay_s, :==, triplet.swing_delay_s,
                    "the extreme clamps at the triplet, it cannot over-lean"
    assert_operator groove(swing: 20.0).swing_delay_s, :==, 0.0,
                    "past the straight side there is nothing to un-lean"
  end
end
