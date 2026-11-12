# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/lane_probe"

# The readiness probe's latency budget follows the lane, not one flat number:
# the gateway lane carries a full system prompt and answers in 18-30 s cold, so
# a flat 20 s dropped the only lane a pinned run had before its first file.
class TestLaneProbeBudget < Minitest::Test
  Probe = Master::Fix::LaneProbe
  GATEWAY = "gateway:openhands_Default"

  def setup
    @saved = ENV.delete("MASTER_FIX_PROBE_S")
  end

  def teardown
    @saved.nil? ? ENV.delete("MASTER_FIX_PROBE_S") : ENV["MASTER_FIX_PROBE_S"] = @saved
  end

  def test_a_gateway_lane_gets_room_for_its_cold_system_prompt
    assert_equal 90, Probe.budget_s(model: GATEWAY)
  end

  def test_an_unlisted_lane_gets_the_default
    assert_equal 20, Probe.budget_s(model: "llm7:codestral-latest")
  end

  def test_the_environment_overrides_one_run
    ENV["MASTER_FIX_PROBE_S"] = "7"

    assert_equal 7, Probe.budget_s(model: GATEWAY)
  end

  def test_a_run_probes_each_lane_under_its_own_budget
    seen = {}
    ask = lambda do |model|
      seen[model] = Probe.budget_s(model: model)
      "OK"
    end

    rows = Probe.run(models: [GATEWAY, "llm7:codestral-latest"], ask:)

    assert rows.all? { |row| row.status == :ok }
    assert_equal 90, seen[GATEWAY]
    assert_equal 20, seen["llm7:codestral-latest"]
  end
end
