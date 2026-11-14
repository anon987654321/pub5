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

    def record_cost(amount, model:, tokens:) = @costs << { amount:, model:, tokens: }
  end

  class FakeBus
    def initialize = @events = []

    def publish(name, payload = nil, **kwargs) = @events << [name, payload || kwargs]
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

  # A stand-in HTTP session that records each request and answers the same body.
  def fake_http(body, seen)
    response = http_ok(body)
    http = Object.new
    http.define_singleton_method(:request) do |request|
      seen << request
      response
    end
    http
  end

  def assert_replicate_http_options(host:, port:, options:)
    assert_equal "api.replicate.com", host
    assert_equal 443, port
    assert_equal true, options.fetch(:use_ssl)
    assert_operator options.fetch(:open_timeout), :<=, 5
    assert_operator options.fetch(:read_timeout), :<=, 10
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

  def assert_replicate_request(seen, path)
    assert_equal "Bearer test-token", seen.first["Authorization"]
    assert_equal path, seen.first.path
  end

  def test_replicate_poll_uses_only_the_validated_api_host_with_bounded_timeouts
    dispatcher = build_dispatcher
    seen = []
    http = fake_http(JSON.generate("status" => "succeeded", "output" => ["ok"]), seen)

    Net::HTTP.stub(:start, lambda { |host, port, **options, &block|
      assert_replicate_http_options(host:, port:, options:)
      block.call(http)
    }) do
      result = fetch_replicate_prediction(dispatcher, "https://api.replicate.com/v1/predictions/a_123-xyz")

      assert result.is_a?(Hash)
      assert_replicate_request(seen, "/v1/predictions/a_123-xyz")
    end
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
