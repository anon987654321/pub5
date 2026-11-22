# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require_relative "../lib/agent/sunset"

class TestSunsetMeasurements < Minitest::Test
  SUNSET = Master::Agent::Sunset
  LEDGER = File.expand_path("../data/sunset.yml", __dir__)

  def test_only_non_negative_integer_counts_are_measured
    assert SUNSET.measured_count?(0)
    assert SUNSET.measured_count?(3)
    refute SUNSET.measured_count?(-1)
    refute SUNSET.measured_count?(1.5)
    refute SUNSET.measured_count?("11964 lines over")
    refute SUNSET.measured_count?("exact counts live in the hook log")
  end

  def test_only_numeric_counts_receive_catch_weight
    assert_equal 1.0, SUNSET.catch_score(3, "active")
    assert_equal 0.0, SUNSET.catch_score(0, "active")
    assert_equal 0.0, SUNSET.catch_score("11964 lines over", "active")
    assert_equal 0.0, SUNSET.catch_score("an instrument reading", "active")
    assert_equal 0.0, SUNSET.catch_score(3, "retired")
  end

  def test_unmeasured_ceremony_is_not_a_retirement_candidate
    advice = SUNSET.advice(48.0, 0.0, measured: false, status: "active")

    assert_includes advice, "unmeasured"
    refute_includes advice, "retire candidate"
  end

  def test_measured_zero_catches_can_still_be_a_retirement_candidate
    advice = SUNSET.advice(48.0, 0.0, measured: true, status: "active")

    assert_includes advice, "retire candidate"
    assert_includes advice, "measured zero catches"
  end

  def test_retired_ceremony_is_not_reconsidered_as_active_cost
    advice = SUNSET.advice(48.0, 0.0, measured: false, status: "retired")

    assert_includes advice, "already retired"
  end

  def test_ledger_uses_numeric_counts_or_null_with_context
    rows = YAML.safe_load_file(LEDGER).fetch("ceremonies")

    refute_empty rows
    rows.each do |row|
      count = row["measured_catches"]
      assert count.nil? || (count.is_a?(Integer) && count >= 0),
             "#{row['id']} must use a non-negative integer or null"
      if count.nil?
        refute_empty row["catch_note"].to_s,
                     "#{row['id']} must explain why its catch count is unmeasured"
      end
    end
  end
end
