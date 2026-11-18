# frozen_string_literal: true

require_relative "test_helper"

# Review::Consensus fans a candidate fix out to three models and ships only on a
# quorum. Which three is a routing decision, and it lived in two places: the
# class held the ids under a comment asking the next reader to keep them in step
# with models.yml. A list kept in step by hand is a list where the next model
# swapped in one place leaves the other voting with a model nothing routes to.
class TestConsensus < Minitest::Test
  def pool = Master.three_mirror_pool

  def test_the_pool_comes_from_models_yml
    declared = Master.load_yaml(Master.data_path("models.yml"))
                     .fetch("three_mirror_redundancy").fetch("pool")

    assert_equal declared, pool
    refute_empty pool, "a quorum over an empty pool approves nothing and says nothing"
  end

  def test_consensus_takes_its_default_from_that_one_source
    assert_equal pool, Master::Review::Consensus.default_models
  end

  def test_local_only_consensus_uses_only_non_cloud_local_models
    previous = ENV["MASTER_LOCAL_ONLY"]
    ENV["MASTER_LOCAL_ONLY"] = "1"

    models = Master::Review::Consensus.default_models

    refute_empty models
    assert_operator models.size, :<=, 3
    # `llama-cli:` is a local lane too (lib/io/lane_selection.rb:59). A prefix
    # allow-list here drifted out of sync with the lane classifier and failed on
    # a correctly local pool, so assert the property the mode actually promises.
    assert(models.all? { |id| Master::Io::LaneSelection.kind(id) == :local })
    refute(models.any? { |id| id.end_with?(":cloud", "-cloud") })
  ensure
    ENV["MASTER_LOCAL_ONLY"] = previous
  end

  # The injection point stays: a caller naming its own models is not overridden
  # by the default, which is what makes the default safe to read from a file.
  def test_an_explicit_pool_wins
    consensus = Master::Review::Consensus.new(agent: nil, models: ["only/one"])

    assert_equal ["only/one"], consensus.instance_variable_get(:@models)
  end

  class RecordingAgent
    attr_reader :calls

    def initialize
      @calls = []
    end

    def ask_once(_prompt, model:, failover:, format:)
      @calls << { model:, failover:, format: }
      '{"approved":true,"reason":"independent vote"}'
    end
  end

  class RecordingBus
    attr_reader :events

    def initialize = (@events = [])
    def publish(event, **payload) = @events << [event, payload]
  end

  def test_writer_family_is_excluded_and_reviewers_cannot_fail_over
    agent = RecordingAgent.new
    bus = RecordingBus.new
    consensus = Master::Review::Consensus.new(
      agent:, event_bus: bus, models: ["claude-sonnet-5-5", "grok-cli:auto", "moonshotai/kimi-k2"], quorum: 2
    )

    approved = consensus.approve_fix?(
      prompt: "test", candidate: "safe",
      violation: { law: "TEST", severity: :error, file: "a.rb", line: 1, message: "fix" },
      author_models: ["anthropic/claude-opus-5-5"]
    )

    assert approved
    assert_equal ["grok-cli:auto", "moonshotai/kimi-k2"], agent.calls.map { |row| row.fetch(:model) }
    assert agent.calls.all? { |row| row.fetch(:failover) == false }
    assert agent.calls.all? { |row| row.fetch(:format) == Master::Review::Consensus::VOTE_SCHEMA }
    assert_equal %w[approved reason], Master::Review::Consensus::VOTE_SCHEMA.fetch(:required)
    result = bus.events.find { |event, _payload| event == "consensus:result" }
    assert_equal ["claude-sonnet-5-5"], result.last.fetch(:excluded_models)
  end

  def test_consensus_blocks_when_author_exclusion_cannot_meet_quorum_and_family_floor
    agent = RecordingAgent.new
    bus = RecordingBus.new
    consensus = Master::Review::Consensus.new(
      agent:, event_bus: bus, models: ["claude-sonnet-5-5", "claude-opus-5-5", "grok-cli:auto"], quorum: 2
    )

    refute consensus.approve_fix?(
      prompt: "test", candidate: "safe",
      violation: { law: "TEST", severity: :error, file: "a.rb", line: 1, message: "fix" },
      author_models: ["anthropic/claude-opus-5-5"]
    )
    assert_empty agent.calls
    blocked = bus.events.find { |event, _payload| event == "consensus:blocked" }
    assert_equal :insufficient_independent_reviewers, blocked.last.fetch(:reason)
    assert_equal 2, blocked.last.fetch(:minimum_families)
  end

  def test_jury_readiness_passes_only_when_each_author_family_leaves_an_independent_quorum
    models = ["zai-cli:auto", "ovh:gpt-oss-120b", "kilo:nvidia/nemotron-3.5-lightning:free"]
    router = Object.new
    router.define_singleton_method(:unreachable_reason) { |_model, wait:| nil }

    readiness = Master::Review::Consensus.stub(:default_models, models) do
      Master::Review::Consensus.stub(:default_quorum, 2) do
        Master::Review::Consensus.jury_readiness(router:)
      end
    end

    assert_predicate readiness, :ready?
    assert_equal :pass, readiness.state
    assert_includes readiness.detail, "survive every author-family exclusion"
  end

  def test_jury_readiness_fails_when_one_unavailable_family_breaks_author_exclusion
    models = ["zai-cli:auto", "ovh:gpt-oss-120b", "kilo:nvidia/nemotron-3.5-lightning:free"]
    router = Object.new
    router.define_singleton_method(:unreachable_reason) do |model, wait:|
      model == "ovh:gpt-oss-120b" ? "set OPENROUTER_API_KEY" : nil
    end

    readiness = Master::Review::Consensus.stub(:default_models, models) do
      Master::Review::Consensus.stub(:default_quorum, 2) do
        Master::Review::Consensus.jury_readiness(router:)
      end
    end

    refute_predicate readiness, :ready?
    assert_equal :fail, readiness.state
    assert_includes readiness.detail, "zhipu author leaves 1/2 voters"
    assert_includes readiness.detail, "set OPENROUTER_API_KEY"
  end

  def test_jury_readiness_does_not_treat_a_pending_provider_probe_as_ready
    models = ["zai-cli:auto", "ovh:gpt-oss-120b", "kilo:nvidia/nemotron-3.5-lightning:free"]
    router = Object.new
    router.define_singleton_method(:unreachable_reason) do |model, wait:|
      model == "zai-cli:auto" ? "checking whether zai-chat is available" : nil
    end

    readiness = Master::Review::Consensus.stub(:default_models, models) do
      Master::Review::Consensus.stub(:default_quorum, 2) do
        Master::Review::Consensus.jury_readiness(router:)
      end
    end

    refute_predicate readiness, :ready?
    assert_equal :unmeasured, readiness.state
    assert_includes readiness.detail, "provider probe did not finish"
  end

  def test_jury_readiness_rejects_a_pool_smaller_than_quorum_without_probing
    router = Object.new
    router.define_singleton_method(:unreachable_reason) { |*| raise "no provider probe should run" }

    readiness = Master::Review::Consensus.stub(:default_models, ["zai-cli:auto"]) do
      Master::Review::Consensus.stub(:default_quorum, 2) do
        Master::Review::Consensus.jury_readiness(router:)
      end
    end

    assert_equal :fail, readiness.state
    assert_includes readiness.detail, "configured pool has 1 model(s), quorum is 2"
  end

  def test_model_family_tracks_the_model_across_provider_aliases
    assert_equal "anthropic", Master::Review::Consensus.model_family("anthropic/claude-opus-5-5")
    assert_equal "anthropic", Master::Review::Consensus.model_family("openrouter:anthropic/claude-sonnet-5-5")
    assert_equal "moonshot", Master::Review::Consensus.model_family("moonshotai/kimi-k2")
    assert_equal "openai", Master::Review::Consensus.model_family("openrouter:openai/o3")
  end

  def test_quorum_comes_from_models_yml_and_fits_the_pool
    declared = Master.load_yaml(Master.data_path("models.yml")).fetch("three_mirror_redundancy").fetch("quorum")
    consensus = Master::Review::Consensus.new(agent: nil)

    assert_equal declared, consensus.instance_variable_get(:@quorum)
    assert_operator pool.size, :>=, declared, "a quorum larger than the pool can never be met"
  end
end
