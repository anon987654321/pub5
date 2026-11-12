# frozen_string_literal: true

require "tempfile"
require_relative "test_helper"

class TestComputePool < Minitest::Test
  class Router
    def reachable?(id)
      id != "down"
    end

    def tool_capable?(id)
      id.include?("qwen") || id.include?("claude")
    end

    def pool(wait: false)
      ["ollama:qwen3.5:27b"]
    end

    def lane_label(id)
      id.start_with?("ollama:") ? "local" : "paid"
    end
  end

  def setup
    @pool = Master::CLI::Routing::ComputePool.new(router: Router.new, root: Dir.mktmpdir)
  end

  def test_ranks_reachable_models
    ids = ["ollama:qwen3.5:27b", "down"]
    assert_equal ["ollama:qwen3.5:27b"], @pool.rank(ids)
  end

  def test_records_success_and_failure
    @pool.record(model: "ollama:qwen3.5:27b", status: :success, latency_ms: 100)
    @pool.record(model: "ollama:qwen3.5:27b", status: :failure, error: "timeout")
    stat = @pool.snapshot.fetch("ollama:qwen3.5:27b")
    assert_equal 2, stat[:calls]
    assert_equal 1, stat[:successes]
    assert_equal 1, stat[:failures]
  end

  def test_task_strengths_boost_matching_capabilities_only
    @pool.instance_variable_set(:@rules, {
      "task_strengths" => {
        "code_generation" => ["coding"],
        "architecture" => %w[reasoning long_context coding],
      },
    })
    candidate = Master::CLI::Routing::ComputePool::Candidate.new(id: "deepseek-coder")

    assert_in_delta 1.04, @pool.send(:task_factor, candidate, :code_generation), 0.001
    assert_in_delta 1.08, @pool.send(:task_factor, candidate, :architecture), 0.001
    assert_equal 1.0, @pool.send(:task_factor, candidate, :unknown_task)
  end

  def test_ollama_is_operator_enabled_and_still_refusable
    old_enabled = ENV.delete("MASTER_OLLAMA_ENABLED")
    old_no_ollama = ENV.delete("MASTER_NO_OLLAMA")
    policy = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml"))
    local_ids = policy.fetch("models").fetch("local").map { |row| row.fetch("id") }

    assert_includes local_ids, "ollama:gemma3:4b"
    assert_includes local_ids, "llama-cli:gguf"
    # The operator wired the local bed on 2026-11-08 ("yes wire ollama after
    # deploy", models.yml): the declaration is enabled in data, the presence
    # probe degrades safely where no daemon listens, and the explicit
    # environment refusals still win over the data file.
    assert_equal true, policy.fetch("ollama").fetch("enabled")
    assert Master::Io::LaneSelection.ollama_enabled?(cfg: policy)

    ENV["MASTER_NO_OLLAMA"] = "1"
    refute Master::Io::LaneSelection.ollama_enabled?(cfg: policy),
           "MASTER_NO_OLLAMA=1 must refuse the lane the data file enables"
    refute_includes Master::Io::LaneSelection.order_or_all(local_ids, cfg: policy), "ollama:gemma3:4b"
    ENV.delete("MASTER_NO_OLLAMA")

    assert_equal "ollama:gemma3:4b", Master::Io::LaneSelection.order_or_all(local_ids, cfg: policy).first

    # A tier may list ollama as a declaration; the constrained local lane leads
    # only where the routing puts it, never by tier promotion alone.
    %w[default primary strong].each do |tier|
      ids = policy.fetch("models").fetch(tier).map { |row| row.fetch("id") }
      order = Master::Io::LaneSelection.order(ids, cfg: policy)
      assert_includes order, "ollama:gemma3:4b" if ids.include?("ollama:gemma3:4b")
    end
    assert_includes policy.fetch("cli_lanes"), "llama-cli"
  ensure
    old_enabled.nil? ? ENV.delete("MASTER_OLLAMA_ENABLED") : ENV["MASTER_OLLAMA_ENABLED"] = old_enabled
    old_no_ollama.nil? ? ENV.delete("MASTER_NO_OLLAMA") : ENV["MASTER_NO_OLLAMA"] = old_no_ollama
  end

  def test_llama_cli_pool_lane_requires_an_explicit_readable_gguf_path
    lane = {
      "binary" => "llama-cli", "kind" => "local",
      "model_path_env" => "MASTER_LLAMA_MODEL",
      "signed_in" => { "args" => ["--version"], "match" => "version" },
      "login" => "set MASTER_LLAMA_MODEL to a local GGUF file",
    }
    router = Master::CLI::Routing::ModelRouter.allocate
    router.instance_variable_set(:@rules, { "cli_lanes" => { "llama-cli" => lane } })
    router.define_singleton_method(:executable_on_path?) { |_binary| true }
    router.define_singleton_method(:probe_value) { |_name, wait:| true }
    old_path = ENV["MASTER_LLAMA_MODEL"]
    ENV.delete("MASTER_LLAMA_MODEL")

    assert_match(/MASTER_LLAMA_MODEL/, router.send(:cli_lane_problem, "llama-cli:gguf", wait: true))
    Tempfile.create(["master-local-model", ".gguf"]) do |model|
      ENV["MASTER_LLAMA_MODEL"] = model.path
      assert_nil router.send(:cli_lane_problem, "llama-cli:gguf", wait: true)
    end
  ensure
    old_path.nil? ? ENV.delete("MASTER_LLAMA_MODEL") : ENV["MASTER_LLAMA_MODEL"] = old_path
  end

  def test_task_strengths_change_the_actual_rank_with_equal_base_scores
    @pool.instance_variable_set(:@rules, {
      "routes" => {},
      "models" => {},
      "task_strengths" => {
        "code_generation" => ["coding"],
        "chitchat" => ["fast"],
      },
    })
    ids = %w[openrouter/deepseek-coder:free openrouter/gemini-flash:free]
    candidate = lambda do |id|
      Master::CLI::Routing::ComputePool::Candidate.new(
        id:,
        quality: 1.0,
        speed: 1.0,
        cost: 1.0,
        context_window: 128_000,
        availability: 1.0,
        tool_support: 1.0,
        success_rate: 1.0,
        latency_factor: 1.0,
        score: { "quality" => 1.0, "speed" => 1.0, "cost" => 1.0 },
      )
    end

    @pool.stub(:candidate, candidate) do
      assert_equal ids.first, @pool.select(ids, task_type: :code_generation)
      assert_equal ids.last, @pool.select(ids, task_type: :chitchat)
    end
  end

  def test_models_configuration_declares_task_specific_strengths
    policy = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml"))
    strengths = policy.fetch("task_strengths")

    assert_includes strengths.fetch("code_generation"), "coding"
    assert_includes strengths.fetch("architecture"), "reasoning"
    assert_includes strengths.fetch("chitchat"), "fast"
  end

  def test_recent_success_out_ranks_a_repeatedly_failing_subscription
    opus = "claude-cli:claude-opus-5-5"
    grok = "grok-cli:auto"
    now = Time.utc(2026, 11, 12, 12).to_f
    @pool.instance_variable_set(:@clock, -> { now })

    # Old failures remain in the lifetime counters but expire from route choice.
    5.times { @pool.record(model: grok, status: :failure, error: "old outage") }
    @pool.instance_variable_set(:@clock, -> { now + Master::CLI::Routing::ComputePool::OUTCOME_WINDOW_S + 1 })
    2.times { @pool.record(model: grok, status: :success, latency_ms: 100) }
    @pool.instance_variable_set(:@clock, -> { now + Master::CLI::Routing::ComputePool::OUTCOME_WINDOW_S + 2 })
    2.times { @pool.record(model: opus, status: :failure, error: "session quota exhausted") }

    candidate = lambda do |id|
      success_rate, latency_factor = @pool.send(:empirical_stats, id)
      Master::CLI::Routing::ComputePool::Candidate.new(
        id:,
        quality: 1.0,
        speed: 1.0,
        cost: 1.0,
        context_window: 128_000,
        availability: 1.0,
        tool_support: 1.0,
        success_rate:,
        latency_factor:,
        score: { "quality" => 1.0, "speed" => 1.0, "cost" => 1.0 },
      )
    end

    @pool.stub(:candidate, candidate) do
      assert_equal [grok, opus], @pool.rank([opus, grok])
    end
  end

  def test_recent_success_evidence_decays_and_expires
    model = "grok-cli:auto"
    now = Time.utc(2026, 11, 12, 12).to_f
    @pool.instance_variable_set(:@clock, -> { now })
    @pool.record(model:, status: :success, latency_ms: 100)

    fresh = @pool.send(:empirical_stats, model).first
    @pool.instance_variable_set(:@clock, -> { now + Master::CLI::Routing::ComputePool::OUTCOME_HALF_LIFE_S })
    decayed = @pool.send(:empirical_stats, model).first
    @pool.instance_variable_set(:@clock, -> { now + Master::CLI::Routing::ComputePool::OUTCOME_WINDOW_S + 1 })
    expired = @pool.send(:empirical_stats, model).first

    assert_operator fresh, :>, decayed
    assert_in_delta 1.0, expired, 0.0001
  end

  def test_recent_model_evidence_survives_a_new_compute_pool
    model = "grok-cli:auto"
    @pool.record(model:, status: :success, latency_ms: 100)
    reloaded = Master::CLI::Routing::ComputePool.new(router: Router.new, root: @pool.instance_variable_get(:@root))

    assert_operator reloaded.send(:empirical_stats, model).last, :>, 1.0
    assert_in_delta Time.now.to_f, reloaded.snapshot.fetch(model).fetch(:last_success_at), 5.0
  end

  def test_snapshot_is_independent
    @pool.record(model: "ollama:qwen3.5:27b", status: :success, latency_ms: 100)
    copy = @pool.snapshot
    copy.fetch("ollama:qwen3.5:27b")[:calls] = 99

    assert_equal 1, @pool.snapshot.fetch("ollama:qwen3.5:27b")[:calls]
  end

  def test_inventory_reports_live_models_and_telemetry
    @pool.record(model: "ollama:qwen3.5:27b", status: :success, latency_ms: 100)

    row = @pool.inventory(task_type: :code_generation).first

    assert_equal "ollama:qwen3.5:27b", row[:id]
    assert_equal 1, row[:rank]
    assert_equal "local", row[:lane]
    assert_equal 1.0, row[:success_rate]
    assert_equal 100.0, row[:latency_ms]
    assert_equal :available, row[:quota_state]
  end

  # Replicate bills per call. Without a model_defs row ComputePool drops its lanes from the ranking, so
  # rank-based selection never picks a paid Replicate lane; score rows for them were proposed and withdrawn.
  def test_paid_replicate_lanes_stay_out_of_the_ranked_pool
    pool = Master::CLI::Routing::ComputePool.new(router: Router.new, root: Master::ROOT)
    ids = Array(pool.instance_variable_get(:@rules)["replicate_chat"]).map { |slug| "replicate:#{slug}" }

    refute_empty ids
    assert_empty pool.rank(ids)
  end
end
