# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/lane_preflight"
require_relative "../lib/fix/lane_probe"
require_relative "../lib/review/consensus"

class TestFixLanePreflight < Minitest::Test
  Preflight = Master::Fix::LanePreflight
  OPUS = "grok-cli:opus"
  GROK = "grok-cli:auto"
  GEMMA = "ollama:gemma3:4b"

  class Agent
    def initialize(routes) = @routes = routes

    def model_for(operation:) = @routes.fetch(operation, OPUS)
  end

  class RoutedAgent < Agent
    def initialize(routes, candidates)
      super(routes)
      @candidates = candidates
    end

    def candidate_models(_message = nil, task_type: nil) = @candidates
  end

  class ProbingAgent < Agent
    def ask_once(*) = "OK"

    def candidate_models(_message = nil, task_type: nil) = [OPUS]
  end

  def setup
    Master::Io::ModelSkipCache.clear!
    Master::Io::LaneQuota.clear_run_drops!
  end

  def teardown
    Master::Io::ModelSkipCache.clear!
    Master::Io::LaneQuota.clear_run_drops!
  end

  def preflight_check(**options)
    Preflight.check(**options)
  end

  def check(routes, live:, env: {})
    lines = []
    result = nil

    Master::Trace::Dmesg.stub(:verbose?, true) do
      Master::Trace::Dmesg.stub(:status, ->(_unit, text, **) { lines << text }) do
        Master::Io::LaneSelection.stub(:live_lanes, live) do
          result = preflight_check(agent: Agent.new(routes), env:)
        end
      end
    end
    [result, lines]
  end

  def test_only_model_free_read_only_observation_skips_provider_admission
    env = {
      "MASTER_SCAN_DETERMINISTIC" => "1",
      "MASTER_FIX_TREE" => "0",
      "MASTER_FIX_DEEP_TRACE" => "0",
      "MASTER_FIX_STRUCTURAL_REVIEW" => "0",
      "MASTER_FIX_PREVIEW" => "0",
    }
    options = { mode: "repair", writes_requested: false, critique: nil, only: nil, env: }
    assert Preflight.deterministic_observation?(**options)
    assert Preflight.deterministic_observation?(**options.merge(only: "fix"))
    [{ writes_requested: true }, { critique: true }, { only: "critique" }, { mode: "audit" }].each do |override|
      refute Preflight.deterministic_observation?(**options.merge(override)), override.inspect
    end
    env.each_key do |key|
      refute Preflight.deterministic_observation?(**options.merge(env: env.reject { |name, _| name == key })), key
    end
  end

  def test_local_only_admission_does_not_require_a_model
    agent = Agent.new({})
    agent.stub(:model_for, ->(**) { flunk "local-only admission must not route a model" }) do
      assert_nil Preflight.check(agent:, env: { "MASTER_LOCAL_ONLY" => "1" })
    end
  end

  def test_preflight_leaves_provider_and_consensus_probes_to_their_owners
    agent = ProbingAgent.new({})

    Master::Review::Consensus.stub(:jury_readiness, ->(**) { flunk "jury readiness is not a run-wide gate" }) do
      Master::Fix::LaneProbe.stub(:run, ->(**) { flunk "provider probing belongs after deterministic fast fixes" }) do
        Master::Trace::Dmesg.stub(:verbose?, false) do
          Master::Io::LaneSelection.stub(:live_lanes, [OPUS]) do
            assert_nil Preflight.check(agent:, env: {})
          end
        end
      end
    end
  end

  def test_a_free_lane_for_a_tree_read_while_opus_is_live_refuses_the_run
    result, lines = check({ tree: GEMMA }, live: [OPUS, GEMMA])

    assert_kind_of Master::Result::Err, result
    assert_match(/tree would run on #{Regexp.escape(GEMMA)} \(local\) while #{OPUS} is live/, result.message)
    assert_equal 1, lines.length, "the refusal is useful; unrelated route rows are not"
  end

  def test_only_a_better_provider_for_the_same_operation_blocks_the_free_floor
    result = nil
    agent = RoutedAgent.new({ tree: GEMMA }, [GROK, GEMMA])

    Master::Trace::Dmesg.stub(:verbose?, false) do
      Master::Trace::Dmesg.stub(:status, ->(*) {}) do
        Master::Io::LaneSelection.stub(:live_lanes, [OPUS, GEMMA]) do
          Master::Io::LaneSelection.stub(:order, ->(ids, **_options) { ids }) do
            result = preflight_check(agent:, env: {})
          end
        end
      end
    end

    assert_kind_of Master::Result::Err, result
    assert_includes result.message, "while #{GROK} is live"
    refute_includes result.message, "while #{OPUS} is live"
  end

  def test_a_live_provider_outside_the_operation_route_does_not_block_the_floor
    result = nil
    agent = RoutedAgent.new({ tree: GEMMA }, [GEMMA])

    Master::Trace::Dmesg.stub(:verbose?, false) do
      Master::Trace::Dmesg.stub(:status, ->(*) {}) do
        Master::Io::LaneSelection.stub(:live_lanes, [OPUS, GEMMA]) do
          result = preflight_check(agent:, env: {})
        end
      end
    end

    assert_nil result
  end

  def test_every_operation_on_a_subscription_lane_starts
    result, lines = check({}, live: [OPUS])

    assert_nil result
    assert_empty lines, "normal fix output does not need one line per operation route"
  end

  def test_a_refused_catalogue_lane_is_named_with_its_reason
    Master::Io::ModelSkipCache.skip!(GROK, reason: "session limit, resets in 2h", category: :rate_limit)
    _result, lines = check({}, live: [GROK], env: { "MASTER_FIX_POOL_DIAGNOSTICS" => "1" })

    assert(lines.any? { |line| line.start_with?("skipped #{GROK}: parked") && line.include?("resets in 2h") })
  ensure
    Master::Io::ModelSkipCache.clear!
  end

  def test_a_run_whose_every_operation_is_free_class_is_refused_before_it_starts
    result, = check({ tree: GEMMA, structural_review: GEMMA, file_write: GEMMA, code_generation: GEMMA },
                    live: [GEMMA])

    assert_kind_of Master::Result::Err, result
    assert_match(/every operation would run on a free-class lane/, result.message)
    assert_includes result.message, "MASTER_FIX_FREE_OK=1"
    assert_equal :human_decision, result.category
  end

  def test_a_free_only_fleet_the_operator_accepted_is_not_refused
    result, = check({ tree: GEMMA, structural_review: GEMMA, file_write: GEMMA, code_generation: GEMMA },
                    live: [GEMMA], env: { "MASTER_FIX_FREE_OK" => "1" })

    assert_nil result
  end

  def test_a_free_lane_is_accepted_when_nothing_better_is_live
    result, = check({ tree: GEMMA, file_write: GEMMA }, live: [GEMMA])

    assert_nil result
  end

  def test_the_operator_can_accept_a_free_lane
    result, = check({ tree: GEMMA }, live: [OPUS, GEMMA], env: { "MASTER_FIX_FREE_OK" => "1" })

    assert_nil result
  end

  def test_default_route_and_skipped_lane_details_are_quiet
    lines = []
    Master::Trace::Dmesg.stub(:verbose?, false) do
      Master::Trace::Dmesg.stub(:status, ->(_unit, text, **) { lines << text }) do
        Master::Io::LaneSelection.stub(:live_lanes, [OPUS]) do
          preflight_check(agent: Agent.new({}), env: {})
        end
      end
    end

    assert_empty lines
  end

  def test_route_rows_require_an_explicit_diagnostic_opt_in
    result, lines = check({}, live: [OPUS], env: { "MASTER_FIX_ROUTE_DIAGNOSTICS" => "1" })

    assert_nil result
    assert_equal Preflight::OPERATIONS.size, lines.count { |line| line.include?(" -> ") }
  end

  def test_probe_uses_lane_selection_order_for_suspended_floor_ranking
    free = "nvidia/nemotron:free"
    live = "grok-cli:auto"
    candidates = [free, live]
    ranked = [live, free]
    observed = []
    selected = nil

    Master::Io::LaneSelection.stub(:order, lambda { |ids, **_options|
      observed << ids
      ranked
    }) do
      selected = Master::Fix::LaneProbe.pick(candidates, 12)
    end

    assert_equal [candidates], observed
    assert_equal ranked, selected
  end

  def test_probe_reserves_capacity_for_all_discovered_keyless_providers
    premium = (1..10).map { |index| "premium#{index}:model" }
    keyless = %w[
      llm7:codestral-latest
      kilo:openrouter/free
      ovh:gpt-oss-120b
      pollinations:openai-fast
    ]
    models = premium + keyless

    Master::Io::LaneSelection.stub(:order, ->(ids, **_options) { ids }) do
      Master::Io::LaneSelection.stub(:kind, ->(id, **_options) { keyless.include?(id) ? :free : :remote }) do
        selected = Master::Fix::LaneProbe.pick(models, 12)
        keyless.each { |id| assert_includes selected, id }
        assert_equal 12, selected.size
      end
    end
  end
end
