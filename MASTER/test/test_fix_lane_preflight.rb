# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/lane_preflight"

class TestFixLanePreflight < Minitest::Test
  Preflight = Master::Fix::LanePreflight
  OPUS = "claude-cli:claude-opus-5-5"
  GEMMA = "ollama:gemma3:4b"

  class Agent
    def initialize(routes) = @routes = routes

    def model_for(operation:) = @routes.fetch(operation, OPUS)
  end

  # A probing agent: the routes agent plus the ask_once the preflight probe
  # needs and a bounded candidate list, so a test never probes the host's
  # real catalogue.
  class ProbingAgent < Agent
    def initialize(routes, answers: false, candidates: %w[fake:a fake:b])
      super(routes)
      @answers = answers
      @candidates = candidates
    end

    def ask_once(*)
      @answers ? "OK" : raise(StandardError, "session limit, resets in 2h")
    end

    def candidate_models(task_type: nil) = @candidates
  end

  def setup
    Master::Io::ModelSkipCache.clear!
    Master::Io::LaneQuota.clear_run_drops!
    Preflight.instance_variable_set(:@probed, nil)
    @probe_env = ENV["MASTER_FIX_PROBE"]
    ENV.delete("MASTER_FIX_PROBE")
  end

  def teardown
    ENV["MASTER_FIX_PROBE"] = @probe_env
    Master::Io::ModelSkipCache.clear!
    Master::Io::LaneQuota.clear_run_drops!
    Preflight.instance_variable_set(:@probed, nil)
  end

  def check(routes, live:, env: {})
    lines = []
    result = nil

    Master::Trace::Dmesg.stub(:status, ->(_unit, text, **) { lines << text }) do
      Master::Io::LaneSelection.stub(:live_lanes, live) do
        result = Preflight.check(agent: Agent.new(routes), env:)
      end
    end
    [result, lines]
  end

  def probe(routes, live:, answers: false, candidates: %w[fake:a fake:b])
    lines = []
    result = nil

    Master::Trace::Dmesg.stub(:status, ->(_unit, text, **) { lines << text }) do
      Master::Io::LaneSelection.stub(:live_lanes, live) do
        # alive? reads host keys and binaries; a test names its own candidates
        # and declares them alive.
        Master::Io::LaneSelection.stub(:alive?, ->(_id) { true }) do
          agent = ProbingAgent.new(routes, answers:, candidates:)
          result = Preflight.check(agent:, env: {})
        end
      end
    end
    [result, lines]
  end

  def test_a_free_lane_for_a_tree_read_while_opus_is_live_refuses_the_run
    result, lines = check({ tree: GEMMA }, live: [OPUS, GEMMA])

    assert_kind_of Master::Result::Err, result
    assert_match(/tree would run on #{Regexp.escape(GEMMA)} \(local\) while #{OPUS} is live/, result.message)
    assert_includes lines, "structural_review -> #{OPUS} (remote)"
  end

  def test_every_operation_on_a_subscription_lane_starts
    result, lines = check({}, live: [OPUS])

    assert_nil result
    assert_equal Preflight::OPERATIONS.size, lines.count { |line| line.include?(" -> ") }
  end

  def test_a_refused_catalogue_lane_is_named_with_its_reason
    Master::Io::ModelSkipCache.skip!(OPUS, reason: "session limit, resets in 2h", category: :rate_limit)
    _result, lines = check({}, live: [OPUS])

    assert(lines.any? { |line| line.start_with?("skipped #{OPUS}: parked") && line.include?("resets in 2h") })
  ensure
    Master::Io::ModelSkipCache.clear!
  end

  def test_a_free_lane_is_accepted_when_nothing_better_is_live
    result, = check({ tree: GEMMA, file_write: GEMMA }, live: [GEMMA])

    assert_nil result
  end

  def test_the_operator_can_accept_a_free_lane
    result, = check({ tree: GEMMA }, live: [OPUS, GEMMA], env: { "MASTER_FIX_FREE_OK" => "1" })

    assert_nil result
  end

  def test_a_run_whose_probed_lanes_all_fail_is_refused
    result, lines = probe({}, live: [OPUS], answers: false)

    assert_kind_of Master::Result::Err, result
    assert_match(/no model lane answered the preflight probe/, result.message)
    assert_match(/MASTER_FIX_PROBE=0/, result.message)
    assert_equal :offline, result.category
    assert(lines.any? { |line| line.include?("lane probe fake (fake:a)") })
  end

  def test_a_catalogue_with_nothing_alive_is_refused_without_a_call
    result, lines = probe({}, live: [OPUS], answers: true, candidates: [])

    assert_kind_of Master::Result::Err, result
    assert_match(/every catalogue lane is marked dead or spent/, result.message)
    refute(lines.any? { |line| line.include?("lane probe") })
  end

  def test_a_run_with_one_answering_lane_starts
    result, = probe({}, live: [OPUS], answers: true)

    assert_nil result
  end

  def test_the_preflight_probe_covers_the_run
    probe({}, live: [OPUS], answers: true)

    assert_predicate Preflight, :probed?
  end

  def test_the_probe_can_be_skipped_by_the_environment
    ENV["MASTER_FIX_PROBE"] = "0"
    result, = probe({}, live: [OPUS], answers: false)

    assert_nil result
    refute_predicate Preflight, :probed?
  end
end
