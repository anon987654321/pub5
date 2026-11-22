# frozen_string_literal: true

require_relative "test_helper"
require "json"

# The Replicate chat lane: it only ever polls the validated api.replicate.com
# host, its poll loop is bounded by a deadline, and the token-cap and
# system-prompt keys are spelled the way each model family declares them,
# because Replicate drops a key the model does not declare rather than
# refusing it.
class TestReplicateSender < Minitest::Test
  class FakeSession
    def initialize = @costs = []

    def record_cost(amount, model:, tokens:, approximate: false) =
      @costs << { amount:, model:, tokens:, approximate: }
  end

  class FakeBus
    def initialize = @events = []

    def publish(name, payload = nil, **kwargs) = @events << [name, payload || kwargs]
  end

  def setup
    @budget_dispatcher = build_dispatcher
    @budget_dispatcher.send(:reset_replicate_chat_budget!)
  end

  def teardown
    @budget_dispatcher&.send(:reset_replicate_chat_budget!)
  end

  def build_dispatcher
    dispatcher = Master::Review::LLMDispatcher.allocate
    dispatcher.instance_variable_set(:@session, FakeSession.new)
    dispatcher.instance_variable_set(:@bus, FakeBus.new)
    dispatcher.instance_variable_set(:@availability, Master::CLI::Routing::AvailabilityPolicy.new(config: {}))
    dispatcher
  end

  def test_replicate_poll_rejects_untrusted_urls_without_opening_a_connection
    dispatcher = build_dispatcher
    prediction = { "urls" => { "get" => "https://169.254.169.254/latest/meta-data/" } }
    result = dispatcher.send(
      :fetch_replicate_prediction,
      prediction,
      headers: { "Authorization" => "Bearer secret" },
      deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30,
    )

    assert result.err?
    assert_equal :policy, result.category
    assert_match(/invalid polling endpoint/, result.message)
  end

  def test_replicate_poll_requires_the_exact_https_api_origin_and_prediction_path
    dispatcher = build_dispatcher
    [
      "http://api.replicate.com/v1/predictions/id",
      "https://api.replicate.com.attacker.invalid/v1/predictions/id",
      "https://attacker.invalid/v1/predictions/id",
      "https://user:pass@api.replicate.com/v1/predictions/id",
      "https://api.replicate.com/v1/models/id",
      "https://api.replicate.com/v1/predictions/id?next=https://attacker.invalid",
    ].each do |url|
      assert_raises(ArgumentError) do
        dispatcher.send(:replicate_poll_uri, replicate_prediction(url))
      end
    end

    uri = dispatcher.send(
      :replicate_poll_uri,
      replicate_prediction("https://api.replicate.com/v1/predictions/a_123-xyz"),
    )
    assert_equal "api.replicate.com", uri.host
    assert_equal "/v1/predictions/a_123-xyz", uri.path
  end

  def http_ok(body)
    response = Net::HTTPOK.allocate
    response.instance_variable_set(:@code, "200")
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@header, {})
    response
  end

  def replicate_prediction(url) = { "urls" => { "get" => url } }

  def fetch_replicate_prediction(dispatcher, url)
    dispatcher.send(
      :fetch_replicate_prediction,
      replicate_prediction(url),
      headers: { "Authorization" => "Bearer test-token" },
      deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30,
    )
  end

  def test_replicate_post_keeps_the_wait_window_separate_from_socket_timeouts
    dispatcher = build_dispatcher
    uri = URI("https://api.replicate.com/v1/models/openai/gpt-5.2/predictions")
    request_options = nil
    response = http_ok("{}")

    Master::Io::SsrfGuard.stub(:request, lambda { |seen_uri, outbound_request, **options|
      request_options = [seen_uri, outbound_request, options]
      response
    }) do
      result = dispatcher.send(:post_json, uri.to_s, { input: { prompt: "hello" } },
                               headers: { "Authorization" => "Bearer test" }, timeout: 70)
      assert_same response, result
    end

    seen_uri, outbound_request, options = request_options
    assert_equal uri, seen_uri
    assert_equal "/v1/models/openai/gpt-5.2/predictions", outbound_request.path
    assert_equal "Bearer test", outbound_request["Authorization"]
    assert_equal 70, options.fetch(:timeout)
    assert_equal 5, options.fetch(:open_timeout)
    assert_equal 70, options.fetch(:read_timeout)
    assert_equal 5, options.fetch(:write_timeout)
  end

  def test_replicate_poll_uses_separate_total_and_socket_deadlines
    dispatcher = build_dispatcher
    uri = URI("https://api.replicate.com/v1/predictions/a_123-xyz")
    request_options = nil
    response = http_ok("{}")

    Master::Io::SsrfGuard.stub(:request, lambda { |seen_uri, outbound_request, **options|
      request_options = [seen_uri, outbound_request, options]
      response
    }) do
      result = dispatcher.send(:replicate_poll_request, uri,
                               { "Authorization" => "Bearer test-token" }, remaining: 30)
      assert_same response, result
    end

    seen_uri, outbound_request, options = request_options
    assert_equal uri, seen_uri
    assert_equal "/v1/predictions/a_123-xyz", outbound_request.path
    assert_equal "Bearer test-token", outbound_request["Authorization"]
    assert_equal 10, options.fetch(:timeout)
    assert_equal 5, options.fetch(:open_timeout)
    assert_equal 10, options.fetch(:read_timeout)
    assert_equal 5, options.fetch(:write_timeout)
  end

  def test_replicate_poll_never_exceeds_the_remaining_prediction_deadline
    dispatcher = build_dispatcher
    captured = nil
    response = http_ok("{}")

    Master::Io::SsrfGuard.stub(:request, lambda { |_uri, _outbound_request, **options|
      captured = options
      response
    }) do
      dispatcher.send(:replicate_poll_request,
                      URI("https://api.replicate.com/v1/predictions/a"),
                      {}, remaining: 3)
    end

    assert_equal 3, captured.fetch(:timeout)
    assert_equal 3, captured.fetch(:open_timeout)
    assert_equal 3, captured.fetch(:read_timeout)
    assert_equal 3, captured.fetch(:write_timeout)
  end

  def test_replicate_poll_stops_on_a_bounded_deadline_and_returns_the_result
    dispatcher = build_dispatcher
    polls = 0
    dispatcher.define_singleton_method(:sleep) { |_seconds| }
    dispatcher.define_singleton_method(:fetch_replicate_prediction) do |_prediction, headers:, deadline:|
      raise "headers lost" unless headers["Authorization"] == "Bearer test"
      raise "deadline missing" unless deadline > Process.clock_gettime(Process::CLOCK_MONOTONIC)

      polls += 1
      { "status" => "succeeded", "output" => ["bounded", " result"] }
    end

    result = dispatcher.send(
      :replicate_output,
      { "status" => "starting", "urls" => { "get" => "https://api.replicate.com/v1/predictions/a" } },
      headers: { "Authorization" => "Bearer test" },
    )

    assert result.ok?
    assert_equal "bounded result", result.value!
    assert_equal 1, polls
  end

  def test_replicate_chat_budget_reserves_max_output_before_posting
    dispatcher = build_dispatcher
    dispatcher.define_singleton_method(:text_prompt_for) { |_messages| "hi" }
    dispatcher.send(:reset_replicate_chat_budget!)
    estimate = dispatcher.send(
      :reserve_replicate_chat_budget!,
      "openai/gpt-5.2",
      messages: [{ role: "user", content: "hi" }],
      sys: "be concise",
    )

    assert_kind_of Float, estimate
    assert_operator estimate, :>, 0.05
    assert_in_delta estimate, dispatcher.send(:replicate_chat_spent), 0.000_001
  ensure
    dispatcher&.send(:reset_replicate_chat_budget!)
  end

  def test_replicate_chat_budget_refuses_over_cap_before_a_network_call
    dispatcher = build_dispatcher
    previous_call = ENV["MASTER_REPLICATE_CALL_CAP_USD"]
    ENV["MASTER_REPLICATE_CALL_CAP_USD"] = "0.01"
    dispatcher.send(:reset_replicate_chat_budget!)

    result = dispatcher.send(
      :reserve_replicate_chat_budget!,
      "openai/gpt-5.2",
      messages: [{ role: "user", content: "hi" }],
      sys: nil,
    )

    assert result.err?
    assert_equal :budget, result.category
    assert_in_delta 0.0, dispatcher.send(:replicate_chat_spent), 0.000_001
  ensure
    previous_call ? ENV["MASTER_REPLICATE_CALL_CAP_USD"] = previous_call : ENV.delete("MASTER_REPLICATE_CALL_CAP_USD")
    dispatcher&.send(:reset_replicate_chat_budget!)
  end

  def test_replicate_chat_budget_stops_at_run_ceiling_across_models
    dispatcher = build_dispatcher
    previous_run = ENV["MASTER_REPLICATE_BUDGET_USD"]
    previous_call = ENV["MASTER_REPLICATE_CALL_CAP_USD"]
    ENV["MASTER_REPLICATE_BUDGET_USD"] = "0.10"
    ENV["MASTER_REPLICATE_CALL_CAP_USD"] = "1.00"
    dispatcher.define_singleton_method(:text_prompt_for) { |_messages| "hi" }
    dispatcher.send(:reset_replicate_chat_budget!)

    first = dispatcher.send(
      :reserve_replicate_chat_budget!, "openai/gpt-5.2",
      messages: [{ role: "user", content: "hi" }], sys: nil
    )
    second = dispatcher.send(
      :reserve_replicate_chat_budget!, "anthropic/claude-opus-5.5",
      messages: [{ role: "user", content: "hi" }], sys: nil
    )

    assert_kind_of Float, first
    assert second.err?
    assert_equal :budget, second.category
  ensure
    previous_run ? ENV["MASTER_REPLICATE_BUDGET_USD"] = previous_run : ENV.delete("MASTER_REPLICATE_BUDGET_USD")
    previous_call ? ENV["MASTER_REPLICATE_CALL_CAP_USD"] = previous_call : ENV.delete("MASTER_REPLICATE_CALL_CAP_USD")
    dispatcher&.send(:reset_replicate_chat_budget!)
  end

  def test_replicate_chat_refuses_to_send_without_an_api_token
    dispatcher = build_dispatcher
    ENV.stub(:[], ->(_key) { nil }) do
      result = dispatcher.send(
        :send_replicate_chat,
        "replicate:owner/model",
        [{ role: "user", content: "hi" }],
        sys: nil,
      )

      assert result.err?
      assert_equal :no_api_key, result.category
    end
  end

  # The operator's environment uses REPLICATE_API_KEY; the sender must accept it.
  def test_replicate_api_key_alias_is_accepted
    previous_token = ENV["REPLICATE_API_TOKEN"]
    previous_key = ENV["REPLICATE_API_KEY"]
    ENV.delete("REPLICATE_API_TOKEN")
    ENV["REPLICATE_API_KEY"] = "test-replicate-key"

    headers = build_dispatcher.send(:replicate_headers)

    assert_equal "Bearer test-replicate-key", headers.fetch("Authorization")
  ensure
    previous_token.nil? ? ENV.delete("REPLICATE_API_TOKEN") : ENV["REPLICATE_API_TOKEN"] = previous_token
    previous_key.nil? ? ENV.delete("REPLICATE_API_KEY") : ENV["REPLICATE_API_KEY"] = previous_key
  end

  # Replicate drops an input key the model does not declare, so the token cap
  # and system prompt must be spelled the way each family's schema declares
  # them or they are silently lost. This pins the family choice.
  def test_replicate_chat_shapes_the_request_for_each_model_family
    dispatcher = build_dispatcher
    shape = ->(slug) { dispatcher.send(:replicate_chat_shape, slug) }

    assert_equal({ tokens: :max_tokens, system: :system_prompt }, shape.call("anthropic/claude-opus-5.5"))
    assert_equal({ tokens: :max_tokens, system: :system_prompt }, shape.call("openai/gpt-oss-120b"))
    assert_equal({ tokens: :max_completion_tokens, system: :system_prompt }, shape.call("openai/gpt-5.2"))
    assert_equal({ tokens: :max_output_tokens, system: :system_instruction }, shape.call("google/gemini-4-carbon"))
  end

  def test_replicate_chat_sends_the_keys_the_selected_family_declares
    dispatcher = build_dispatcher
    captured = nil
    dispatcher.define_singleton_method(:replicate_headers) { { "Authorization" => "Bearer test" } }
    dispatcher.define_singleton_method(:text_prompt_for) { |_messages| "hi" }
    dispatcher.define_singleton_method(:reserve_replicate_chat_budget!) { |*args, **kwargs| 0.01 }
    dispatcher.define_singleton_method(:post_json) do |_url, body, **|
      captured = body.fetch(:input)

      ok = Net::HTTPOK.new("1.1", "200", "OK")
      ok.instance_variable_set(:@body, '{"status":"succeeded","output":"ok"}')
      ok.instance_variable_set(:@read, true)
      ok
    end

    dispatcher.send(:send_replicate_chat, "replicate:google/gemini-4-carbon",
                    [{ role: "user", content: "hi" }], sys: "be terse")

    assert_equal "be terse", captured[:system_instruction]
    assert_equal 4096, captured[:max_output_tokens]
    refute captured.key?(:max_tokens), "the Gemini family takes max_output_tokens, not max_tokens"
    refute captured.key?(:system_prompt), "the Gemini family takes system_instruction, not system_prompt"
  end
end
