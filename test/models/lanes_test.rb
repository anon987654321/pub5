# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../master/models/dispatch"

# Moved from pub4 test_lane_state.rb and test_fix_model_gate.rb: one breaker
# per lane, one router over registry/models.yml, one gate before the call.
class LanesTest < Minitest::Test
  include TestHelper

  def catalog = @catalog ||= Models::Catalog.new

  def lanes(clock = -> { @now }, store: nil) = Models::Lanes.new(catalog:, store:, clock:)

  def setup = @now = 1_000.0

  def test_lane_of_names_the_unit_that_fails_together
    assert_equal "claude-cli", catalog.lane_of("claude-cli:claude-opus-5-5")
    assert_equal "anthropic", catalog.lane_of("claude-opus-5-5")
    assert_equal "openrouter", catalog.lane_of("nvidia/nemotron-3-super-120b-a12b:free")
    assert_equal :claude, catalog.kind("claude-cli:claude-sonnet-5-5")
    assert_equal :http, catalog.kind("deepseek-chat")
    assert_nil catalog.kind("web-chat:grok"), "no moved code reaches the browser lanes"
  end

  def test_a_model_no_store_refuses_is_usable
    assert lanes.usable?("claude-cli:claude-opus-5-5")
  end

  def test_a_failed_lane_names_its_reason_and_climbs_the_ladder
    l = lanes
    line = l.failed("claude-cli:claude-opus-5-5", "exit 1\nmore", category: :error)

    assert_equal "lanes0: claude-cli cooling off 30s (exit 1)", line
    assert_match(/claude-cli: cooling off 30s \(exit 1\)/, l.verdict("claude-cli:claude-sonnet-5-5"),
                 "the lane, not the one model, is cooling off")
    @now += 31
    assert l.usable?("claude-cli:claude-opus-5-5"), "the cool-off ends: the next call is the half-open probe"
    assert_match(/1m/, l.failed("claude-cli:claude-opus-5-5", "again"))
    @now += 61
    assert_match(/5m/, l.failed("claude-cli:claude-opus-5-5", "again"))
    @now += 301
    l.succeeded("claude-cli:claude-opus-5-5")
    assert_match(/30s/, l.failed("claude-cli:claude-opus-5-5", "fresh"), "one answer closes the breaker")
  end

  def test_a_spent_quota_is_not_a_cool_off
    l = lanes
    l.failed("claude-cli:claude-opus-5-5", "You've hit your session limit", category: :quota)

    refute l.usable?("claude-cli:claude-opus-5-5")
    refute l.cooling?("claude-cli:claude-opus-5-5"), "a quota is not worth waiting out"
  end

  def test_a_lane_dead_by_hand_is_refused_before_anything_else
    assert_match(/down by hand/, lanes.verdict("codex-cli:auto"))
  end

  def test_the_breaker_is_shared_through_its_file
    sandbox do |root|
      w = world(root, { read: ["log/master/*"], write: ["log/master/*"] })
      lanes(store: Models::Lanes::Store.new(w)).failed("grok-cli:auto", "no answer in 300s", category: :timeout)

      assert lanes(store: Models::Lanes::Store.new(w)).cooling?("grok-cli:auto"), "a second process reads the same breaker"
      assert_equal 0o600, File.stat(File.join(root, Models::Lanes::PATH)).mode & 0o777
    end
  end

  def test_the_chain_keeps_registry_order_and_drops_what_nothing_reaches
    router = Models::Router.new(catalog:, lanes: lanes, knobs: knobs)
    chain = router.chain("code")

    assert_equal "claude-cli:claude-opus-5-5", chain.first
    refute_includes chain, "web-chat:grok"
    refute_includes chain, "claude-opus-5-5", "an HTTP provider without a key never enters the chain"
    assert_includes Models::Router.new(catalog:, lanes:, knobs: knobs("ANTHROPIC_API_KEY" => "k")).chain("code"),
                    "claude-opus-5-5"
  end

  def test_a_pin_is_the_only_lane
    router = Models::Router.new(catalog:, lanes:, knobs: knobs("PUB5_MODEL" => "claude-cli:claude-sonnet-5-5"))
    assert_equal ["claude-cli:claude-sonnet-5-5"], router.chain("chitchat")
  end

  def test_text_is_classified_into_a_route
    router = Models::Router.new(catalog:, lanes:, knobs: knobs)
    assert_equal "chitchat", router.classify("hei!")
    assert_equal "refactoring", router.classify("refactor the lane store")
    assert_equal "exploration", router.classify("the weather in Bergen")
  end
end

class GateTest < Minitest::Test
  Gate = Models::Gate
  MODEL = "claude-cli:claude-opus-5-5"

  def setup
    @now = 0.0
    @lanes = Models::Lanes.new(catalog: Models::Catalog.new, clock: -> { @now })
  end

  def gate(loads: [nil], deadline: nil)
    @slept = []
    sleeper = lambda do |s|
      @slept << s
      @now += s
    end
    load = -> { loads.size > 1 ? loads.shift : loads.first }
    Gate.new(lanes: @lanes, load:, cpus: 8, sleeper:, clock: -> { @now }, deadline:)
  end

  def test_a_pinned_lane_in_its_cool_off_is_waited_out
    @lanes.failed(MODEL, "malformed tool-call response")
    gate.before_call([MODEL])

    assert_equal [Gate::POLL_S] * 2, @slept, "30s of cool-off is two 15s polls"
    assert @lanes.usable?(MODEL)
  end

  def test_a_loaded_host_is_given_time_to_come_down
    gate(loads: [12.9, 12.5, 6.0]).before_call([])
    assert_equal [Gate::POLL_S] * 2, @slept
  end

  def test_the_load_wait_is_bounded
    gate(loads: [20.0]).before_call([])
    assert_equal Gate::LOAD_WAIT_MAX_S / Gate::POLL_S, @slept.size
  end

  def test_nothing_waits_near_a_deadline
    @lanes.failed(MODEL, "quiet")
    gate(loads: [20.0], deadline: Gate::RESERVE_S).before_call([MODEL])
    assert_empty @slept
  end

  def test_a_lane_that_answers_and_a_quiet_host_cost_nothing
    assert_equal 0, gate(loads: [3.0]).before_call([MODEL])
    assert_empty @slept
  end
end
