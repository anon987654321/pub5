# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/run_ledger"

# The times a /fix run allows come from data/budgets.yml#fix_time for the lane it is pinned to.
class FixTimeTest < Minitest::Test
  Budget = Master::Fix::FixTime

  def setup
    @saved = Budget::KEYS.values.to_h { |key| [key, ENV.delete(key)] }
  end

  def teardown
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  # The default must hold a strong paid lane's repair (a proposal, a retry and a
  # verifier call, one to four minutes each): the old 240 s file / 1800 s run
  # timed out every lane that had no named entry, DeepSeek and Replicate included.
  def test_a_run_with_no_pin_or_an_unlisted_lane_gets_the_default
    assert_equal 900, Budget.file_s(model: nil)
    assert_equal 7200, Budget.run_s(model: "grok-cli:auto")
    assert_equal 900, Budget.stall_s(model: "deepseek-reasoner")
  end

  # A lane entry names only what it changes; the rest fall back to the default.
  def test_a_lane_overrides_only_the_field_it_names
    assert_equal 90, Master::Fix::LaneProbe.budget_s(model: "gateway:glm-5.3")
    assert_equal 900, Budget.file_s(model: "gateway:glm-5.3")
  end

  def test_the_environment_overrides_one_run
    ENV["MASTER_FIX_FILE_BUDGET_S"] = "7"

    assert_equal 7, Budget.file_s(model: nil)
  end
end
