# frozen_string_literal: true

require_relative "test_helper"

class TestModelHealth < Minitest::Test
  Registry = Master::CLI::CommandRegistry

  Pool = Struct.new(:stats, :rows) do
    def initialize(stats = {}, rows = nil)
      super(stats, rows)
    end

    def snapshot = stats
    def inventory(task_type:) = rows
  end

  Router = Struct.new(:compute_pool) do
    def unreachable_reason(*) = nil
  end

  Agent = Struct.new(:model_router)

  def report(stats)
    Registry.model_health(agent: Agent.new(Router.new(Pool.new(stats))))
  end

  def test_health_report_summarizes_success_failure_and_latency
    result = report(
      "local:small" => { calls: 4, successes: 4, failures: 0, latency_ms: 850.0 },
      "gateway:unstable" => {
        calls: 5, successes: 2, failures: 3, latency_ms: 1_200.0, first_token_ms: 550.0,
        last_error: "Authorization: Bearer must-never-be-rendered"
      },
    )

    assert_includes result, "model health: 2 models, 9 calls, success=66.7%, failures=3"
    assert_includes result, "gateway:unstable  calls=5 ok=2 fail=3 success=40.0% avg_ok=1200ms ttft=550ms"
    assert_includes result, "local:small  calls=4 ok=4 fail=0 success=100.0% avg_ok=850ms"
    refute_includes result, "must-never-be-rendered"
  end

  def test_model_health_is_documented_and_reachable_through_the_model_subcommand
    assert_includes Registry.help_text("model"), "/model health"

    result = Registry.dispatch_model(
      agent: Agent.new(Router.new(Pool.new({
        "provider:model" => { calls: 2, successes: 1, failures: 1, latency_ms: 400.0 },
      }))),
      config: nil,
      metrics: nil,
      root: Master::ROOT,
      arg: "health",
    )

    assert_includes result, "model health: 1 models, 2 calls, success=50.0%, failures=1"
  end

  def test_health_report_states_when_no_calls_have_been_recorded
    assert_equal(
      "model health: no recorded calls yet; /model compute lists reachable lanes",
      report("untried" => { calls: 0, successes: 0, failures: 0, latency_ms: 0.0 }),
    )
  end

  def test_model_compute_shows_calls_and_measured_latency
    rows = [{
      rank: 1,
      id: "ollama:gemma3:4b",
      lane: "local",
      quota_remaining: nil,
      quota_state: :available,
      calls: 4,
      success_rate: 0.75,
      latency_ms: 325.7,
      first_token_ms: 90.5,
    }]
    router = Router.new(Pool.new({}, rows))

    result = Registry.dispatch_model(
      agent: Agent.new(router),
      config: nil,
      metrics: nil,
      root: Master::ROOT,
      arg: "compute",
    )

    assert_equal "1. ollama:gemma3:4b  local  available  success=75% calls=4 avg_ok=326ms ttft=91ms", result
  end

  def test_health_report_caps_the_number_of_model_rows
    stats = 35.times.to_h do |index|
      ["provider:model-#{index}", { calls: 1, successes: 1, failures: 0, latency_ms: 100.0 }]
    end

    result = report(stats)

    assert_includes result, "... 5 more models"
    assert_equal 32, result.lines.size
  end

  def test_model_doctor_reports_isolated_discovery_failures_without_raw_errors
    router = Router.new(Pool.new)
    router.define_singleton_method(:pool) { |wait:| ["glm-5.3-flash"] }
    router.define_singleton_method(:pool_discovery_errors) do
      [{ "lane" => "openrouter_catalog", "error" => "Net::OpenTimeout" }]
    end

    result = Registry.dispatch_model(
      agent: Agent.new(router),
      config: nil,
      metrics: nil,
      root: Master::ROOT,
      arg: "doctor",
    )

    assert_includes Registry.help_text("model"), "/model doctor"
    assert_includes result, "reachable=1; discovery_errors_since_start=1"
    assert_includes result, "openrouter_catalog raised Net::OpenTimeout during discovery"
    assert_includes result, "other lanes remain eligible"
    refute_includes result, "Authorization"
  end

  def test_model_doctor_classifies_provider_failures_without_rendering_raw_error_text
    stats = {
      "grok-cli:auto" => {
        calls: 3, successes: 0, failures: 3,
        last_error: "provider call exceeded its deadline: outbound request exceeded 5s; Authorization: Bearer secret",
        last_failure_at: 1_795_219_200.0,
      },
      "glm-5.3-flash" => { calls: 1, successes: 1, failures: 0, last_error: nil },
    }
    router = Router.new(Pool.new(stats))
    router.define_singleton_method(:pool) { |wait:| ["glm-5.3-flash"] }
    router.define_singleton_method(:pool_discovery_errors) { [] }
    router.define_singleton_method(:lane_label) { |id| id.start_with?("grok-cli:") ? "subscription" : "paid" }

    result = Registry.dispatch_model(
      agent: Agent.new(router),
      config: nil,
      metrics: nil,
      root: Master::ROOT,
      arg: "doctor",
    )

    assert_includes result, "models_with_recorded_failures=1"
    assert_includes result, "grok-cli:auto lane=subscription failures=3 last_error=timeout last_failure_utc=2026-11-21T00:00:00Z"
    refute_includes result, "Authorization"
    refute_includes result, "secret"
  end


  def test_model_doctor_failure_categories_are_stable
    {
      "outbound request exceeded its deadline" => "timeout",
      "401 Unauthorized: invalid API key" => "authentication",
      "429 rate limit exceeded" => "quota",
      "SocketError: getaddrinfo failed" => "connectivity",
      "unspecified provider failure" => "provider_error",
    }.each do |raw, expected|
      assert_equal expected, Registry.provider_failure_kind(raw)
    end
  end

end
