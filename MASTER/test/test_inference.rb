# frozen_string_literal: true

require_relative "test_helper"

class TestInference < Minitest::Test
  class FakeAgent
    attr_reader :prompts

    def initialize
      @prompts = []
      @count = 0
    end

    def ask_once(prompt, **)
      @prompts << prompt
      @count += 1
      case prompt
      when /List 3 independent/
        "1. Alpha\n2. Beta\n3. Gamma"
      when /Expand this answer point/
        "expanded #{@count}"
      when /Synthesize the following independent/
        "final synthesis"
      else
        "candidate #{@count}"
      end
    end
  end

  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, **payload)
      @events << [event, payload]
    end
  end

  def setup
    @agent = FakeAgent.new
    @bus = FakeBus.new
  end

  def test_repeat_transform_repeats_complete_prompt
    prompt = "full context\nquestion"
    repeated = Master::Review::Inference::Transforms.repeat(prompt)

    assert_equal "#{prompt}\n\n#{prompt}", repeated
  end

  def test_self_consistency_votes_on_extracted_answers
    agent = Class.new(FakeAgent) do
      def ask_once(prompt, **)
        super
        ["A\nANSWER: red", "B\nANSWER: blue", "C\nANSWER: red"][@prompts.length - 1]
      end
    end.new

    result = Master::Review::Inference.run(
      agent:,
      event_bus: @bus,
      prompt: "choose",
      strategy: :self_consistency,
      samples: 3,
      max_calls: 3,
      extractor: ->(text) { text[/ANSWER:\s*(\w+)/, 1] },
    )

    assert result.ok?
    assert_equal "red", result.value![:winner]
    assert_equal 2, result.value![:votes]["red"]
    assert_in_delta 2.0 / 3.0, result.value![:confidence]
  end

  def test_skeleton_expands_points_in_parallel_and_synthesizes
    result = Master::Review::Inference.run(
      agent: @agent,
      event_bus: @bus,
      prompt: "design a pipeline",
      strategy: :skeleton,
      points: 3,
      max_calls: 5,
    )

    assert result.ok?
    assert_equal %w[Alpha Beta Gamma], result.value![:skeleton]
    assert_equal "final synthesis", result.value![:final]
    assert_equal 5, @agent.prompts.size
  end

  def test_parallel_search_preserves_order_and_bounds_concurrent_calls
    mutex = Mutex.new
    active = 0
    maximum = 0
    agent = Object.new
    agent.define_singleton_method(:ask_once) do |prompt, **|
      mutex.synchronize do
        active += 1
        maximum = [maximum, active].max
      end
      sleep 0.005
      prompt
    ensure
      mutex.synchronize { active -= 1 }
    end
    prompts = (1..25).map { |index| "prompt-#{index}" }

    rows = Master::Review::Inference::Search.send(:parallel, agent, prompts, temperature: 0.2)

    assert_equal prompts, rows
    assert_operator maximum, :>, 1
    assert_operator maximum, :<=, Master::Review::Inference::Search::MAX_PARALLEL
  end

  def test_parallel_search_joins_siblings_before_propagating_worker_failure
    started = Queue.new
    release = Queue.new
    finished = Queue.new
    agent = Object.new
    agent.define_singleton_method(:ask_once) do |prompt, **|
      started << prompt
      raise "inference worker failed" if prompt == "FAIL"

      release.pop
      finished << prompt
      "ok"
    end
    result = Queue.new
    coordinator = Thread.new do
      begin
        Master::Review::Inference::Search.send(:parallel, agent, %w[FAIL SLOW], temperature: 0.2)
        result << :unexpected_success
      rescue StandardError => error
        result << error
      end
    end

    assert_equal %w[FAIL SLOW], [started.pop, started.pop].sort
    sleep 0.02
    assert coordinator.alive?, "the coordinator must wait for the sibling model call"
    release << :continue
    coordinator.join
    error = result.pop

    assert_instance_of RuntimeError, error
    assert_equal "inference worker failed", error.message
    assert_equal "SLOW", finished.pop
  end

  def test_parallel_search_joins_partial_startup_before_returning_thread_error
    started = Queue.new
    finished = Queue.new
    original_new = Thread.method(:new)
    calls = 0
    agent = Object.new
    agent.define_singleton_method(:ask_once) do |prompt, **|
      started << prompt
      finished << prompt
      prompt
    end

    Thread.stub(:new, lambda { |*args, **kwargs, &block|
      calls += 1
      raise ThreadError, "thread limit reached" if calls == 2

      original_new.call(*args, **kwargs, &block)
    }) do
      error = assert_raises(ThreadError) do
        Master::Review::Inference::Search.send(:parallel, agent, %w[first second], temperature: 0.2)
      end
      assert_equal "thread limit reached", error.message
    end

    assert_equal "first", started.pop
    assert_equal "first", finished.pop
    assert_equal 2, calls
  end

  def test_denial_forces_each_round_to_carry_the_previous_answer
    result = Master::Review::Inference.run(
      agent: @agent,
      prompt: "solve this",
      strategy: :denial,
      constraints: %w[loops recursion],
      rounds: 2,
      max_calls: 2,
    )

    assert result.ok?
    assert_equal 2, result.value![:rounds]
    assert_match(/Previous candidate/, @agent.prompts.last)
    assert_match(/recursion/, @agent.prompts.last)
  end

  def test_strange_world_builder_never_receives_the_problem
    result = Master::Review::Inference.run(
      agent: @agent,
      prompt: "solve the repository problem",
      strategy: :strange_world,
      seeds: ["gravity"],
      max_calls: 3,
    )

    assert result.ok?
    world_prompt = @agent.prompts.first
    refute_includes world_prompt, "repository problem"
    assert_equal "gravity", result.value![:seed]
  end

  def test_perspective_transition_produces_three_views_and_a_judge
    result = Master::Review::Inference.run(
      agent: @agent,
      prompt: "should this change ship?",
      strategy: :perspective,
      max_calls: 4,
    )

    assert result.ok?
    assert_equal %i[direct expert observer], result.value![:perspectives].keys
    assert_equal 4, @agent.prompts.size
  end

  def test_gepa_keeps_a_pareto_candidate_without_mutating_the_source_prompt
    metric = ->(example, output) { example[:expected] == output ? 1.0 : 0.0 }
    result = Master::Review::Inference.run(
      agent: @agent,
      prompt: "Answer exactly with the expected value.",
      strategy: :gepa,
      dataset: [{ input: "x", expected: "candidate 1" }],
      metric:,
      generations: 0,
      population: 1,
    )

    assert result.ok?
    assert_equal "Answer exactly with the expected value.", result.value![:winner].prompt
  end

  def test_policy_maps_detail_finding_to_repeat_without_guessing
    result = Master::Review::Inference.run(
      agent: @agent,
      prompt: "find the name",
      task_type: :detail_finding,
      max_calls: 1,
    )

    assert result.ok?
    assert_equal :repeat, result.value![:strategy]
    assert_equal 1, @agent.prompts.size
    assert_equal "find the name\n\nfind the name", @agent.prompts.first
  end
end
