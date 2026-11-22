# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/fix/run_budget"

# CLI lanes without provider usage data still count: an estimate from their
# request and response size keeps the /fix budget honest.
class TestCliLaneUsage < Minitest::Test
  Ledger = Struct.new(:costs) do
    def record_cost(amount, model:, tokens:, approximate: false)
      costs << { amount:, model:, tokens:, approximate: }
    end
  end

  OK = Struct.new(:success?).new(true)

  def dispatcher(session, out)
    lane = Master::Review::LLMDispatcher.allocate
    lane.instance_variable_set(:@session, session)
    lane.instance_variable_set(:@bus, nil)
    lane.instance_variable_set(:@availability, Master::CLI::Routing::AvailabilityPolicy.new(config: {}))
    lane.define_singleton_method(:capture3_with_timeout) do |_timeout, *args, **|
      (@asked ||= []) << args
      [out, "", OK]
    end
    lane
  end

  def budget(root)
    Master::Fix::RunBudget.new(root:, max_passes: 1, env: {}, wall: -> { Time.at(0) }, out: ->(line) { line },
                               say: ->(text) { text }, poll_seconds: 0).start!
  end

  def test_a_cli_lane_without_usage_bills_an_approximate_token_estimate
    ledger = Ledger.new([])
    lane = dispatcher(ledger, "x" * 400)
    lane.define_singleton_method(:find_agy_bin) { "/bin/agy" }

    result = lane.send(:send_agy_cli, "auto", [{ role: "user", content: "y" * 800 }], sys: nil)

    assert_predicate result, :ok?
    row = ledger.costs.last
    assert_operator row[:tokens], :>=, 300
    assert_in_delta 0.0, row[:amount]
    assert row[:approximate], "an estimate must say it is one"
  end
end
