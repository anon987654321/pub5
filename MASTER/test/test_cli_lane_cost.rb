# frozen_string_literal: true

require_relative "test_helper"

# A /fix run forced through grok-cli reached the $10 session budget and
# refused every repair after it, though a subscription lane costs nothing
# per call. The estimate the circuit breaker charges is zero for such a lane.
# On 2026-11-16 the same fiction parked the keyless kilo and ovh lanes
# ("single call $1.1541 exceeds max_per_file $1.0") with no keyed lane on
# the host, so the /fix model phase went offline although the free lanes
# answered. A lane that bills nothing per call estimates as zero.
class TestCliLaneCost < Minitest::Test
  def estimate(model) = Master::Review::LLMDispatcher.allocate.send(:estimate_cost, "x" * 40_000, model)

  def setup = Master::Io::LaneSelection.reset_hosted_resolver!
  def teardown = Master::Io::LaneSelection.reset_hosted_resolver!

  def test_a_subscription_lane_costs_nothing_per_call
    assert_in_delta 0.0, estimate("grok-cli:opus")
  end

  def test_a_free_tier_lane_costs_nothing_per_call
    assert_in_delta 0.0, estimate("nvidia/nemotron-3-super-120b-a12b:free")
  end

  def test_a_local_lane_costs_nothing_per_call
    assert_in_delta 0.0, estimate("ollama:gemma3:4b")
  end

  def test_an_api_lane_is_still_charged
    assert_operator estimate("openrouter/some-model"), :>, 0.0
  end
end
