# frozen_string_literal: true

require_relative "test_helper"

class TestRailsApiClient < Minitest::Test
  Client = Master::Io::RailsApiClient

  def setup
    @dir = Dir.mktmpdir("rails-api-client")
    @client = Client.new(
      base_url: "https://rails.example.test", auth_strategy: :api_key,
      api_key: "test-secret", log_root: @dir, retries: 0,
    )
  end

  def teardown
    FileUtils.remove_entry(@dir) if File.directory?(@dir)
  end

  def test_configuration_does_not_claim_that_a_request_was_made
    state = @client.status
    assert_equal "CONFIGURED", state[:status]
    assert_equal "NOT_RUN", state[:live_request]
  end

  def test_refuses_an_absolute_or_cross_origin_request_path
    assert @client.send(:resolve, "/api/status").is_a?(URI::HTTPS)
    assert_raises(ArgumentError) { @client.send(:resolve, "https://other.example/api") }
    assert_raises(ArgumentError) { @client.send(:resolve, "//other.example/api") }
  end

  def test_unknown_authentication_strategy_is_rejected
    assert_raises(ArgumentError) do
      Client.new(base_url: "https://rails.example.test", auth_strategy: :unknown)
    end
  end

  def test_http_error_is_an_error_not_a_success
    response = Client::Response.new(status: 404, headers: {}, body: "missing", elapsed_s: 0.01)
    @client.define_singleton_method(:destination_address) { |_uri| "203.0.113.10" }
    @client.define_singleton_method(:perform) { |_method, _uri, **_options| response }

    result = @client.get("/api/status")
    assert result.err?
    assert_equal :validation, result.category
  end

  def test_non_idempotent_write_is_not_retried
    calls = 0
    @client.define_singleton_method(:destination_address) { |_uri| "203.0.113.10" }
    @client.define_singleton_method(:perform) do |_method, _uri, **_options|
      calls += 1
      raise IOError, "offline"
    end

    result = @client.post("/api/events", body: { event: "created" })
    assert result.err?
    assert_equal 1, calls
  end

  def test_get_retries_a_server_error_but_stops_when_a_success_arrives
    client = Client.new(
      base_url: "https://rails.example.test", auth_strategy: :api_key,
      api_key: "test-secret", log_root: @dir, retries: 1, backoff: 0,
    )
    calls = 0
    client.define_singleton_method(:destination_address) { |_uri| "203.0.113.10" }
    client.define_singleton_method(:perform) do |_method, _uri, **_options|
      calls += 1
      status = calls == 1 ? 503 : 200
      Client::Response.new(status:, headers: {}, body: "", elapsed_s: 0.01)
    end

    result = client.get("/api/status")
    assert result.ok?
    assert_equal 2, calls
  end

  def test_audit_does_not_persist_identifier_bearing_path_segments
    @client.define_singleton_method(:destination_address) { |_uri| "203.0.113.10" }
    @client.define_singleton_method(:perform) do |_method, _uri, **_options|
      Client::Response.new(status: 200, headers: {}, body: "ok", elapsed_s: 0.01)
    end
    assert @client.get("/api/users/secret-user-123/profile").ok?
    audit = File.read(File.join(@dir, "rails_api_client", "audit.ndjson"))
    refute_includes audit, "secret-user-123"
    assert_includes audit, "path_digest"
  end

  def test_explicit_public_pin_refuses_a_mixed_dns_answer_set
    Master::Io::SsrfGuard.stub(
      :resolve_addresses, ["93.184.216.34", "127.0.0.1"]
    ) do
      assert_raises(ArgumentError) do
        Client.new(
          base_url: "https://rails.example.test", auth_strategy: :api_key,
          api_key: "test-secret", pinned_address: "93.184.216.34", log_root: @dir
        )
      end
    end
  end

  def test_explicit_public_pin_accepts_only_all_public_answers
    Master::Io::SsrfGuard.stub(
      :resolve_addresses, ["93.184.216.34", "8.8.8.8"]
    ) do
      client = Client.new(
        base_url: "https://rails.example.test", auth_strategy: :api_key,
        api_key: "test-secret", pinned_address: "8.8.8.8", log_root: @dir
      )
      assert_equal "8.8.8.8", client.instance_variable_get(:@pinned_address)
    end
  end

  def test_http_attempt_has_a_hard_deadline_even_when_the_peer_drips
    client = Client.new(
      base_url: "https://rails.example.test", auth_strategy: :api_key,
      api_key: "test-secret", log_root: @dir, timeout: 0.01, retries: 0
    )
    http = Object.new
    http.define_singleton_method(:start) { |&block| block.call(self) }
    http.define_singleton_method(:request) { |_request, &_response| sleep 0.05 }

    Master::Io::SsrfGuard.stub(:http_for, http) do
      assert_raises(Timeout::Error) do
        client.send(
          :perform, :get, URI("https://rails.example.test/api/status"),
          address: "93.184.216.34", body: nil, headers: {}
        )
      end
    end
  end

  def test_private_http_origin_requires_an_explicit_pinned_address
    assert_raises(ArgumentError) do
      Client.new(base_url: "http://127.0.0.1:3000", auth_strategy: :api_key, api_key: "x")
    end
    client = Client.new(
      base_url: "http://127.0.0.1:3000", auth_strategy: :api_key,
      api_key: "x", pinned_address: "127.0.0.1", log_root: @dir,
    )
    assert_equal "127.0.0.1", client.instance_variable_get(:@pinned_address)
  end
end
