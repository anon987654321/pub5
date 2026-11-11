# frozen_string_literal: true

require_relative "test_helper"
require "json"

class TestReplicateClientTrain < Minitest::Test
  def test_training_weights_url_from_hash
    client = Master::Io::ReplicateClient.new(token: "r8_test")
    training = {
      "output" => {
        "version" => "owner/model:abc",
        "weights" => "https://replicate.delivery/yhqm/example/trained_model.tar",
      },
    }
    assert_equal(
      "https://replicate.delivery/yhqm/example/trained_model.tar",
      client.training_weights_url(training),
    )
  end

  def test_training_weights_url_string_output
    client = Master::Io::ReplicateClient.new(token: "r8_test")
    assert_equal "owner/model:abc", client.training_weights_url("output" => "owner/model:abc")
  end

  def test_lora_trainer_constant
    assert_equal "ostris/flux-dev-lora-trainer", Master::Io::ReplicateClient::LORA_TRAINER
  end

  def test_create_model_requires_owner_name
    client = Master::Io::ReplicateClient.new(token: "r8_test")
    assert_raises(ArgumentError) { client.create_model("noneslash") }
  end
end

class TestReplicateClientRetry < Minitest::Test
  Client = Master::Io::ReplicateClient

  class StreamingResponse
    attr_reader :code, :read_count, :body

    def initialize(code: "200", chunks: [], headers: {})
      @code = code
      @chunks = chunks.map { |chunk| chunk.to_s.b }
      @body = @chunks.join
      @headers = headers.transform_keys { |name| name.downcase }
      @read_count = 0
    end

    def [](name) = @headers[name.downcase]

    def read_body
      @read_count += 1
      @chunks.each { |chunk| yield chunk }
    end
  end

  def with_http_responses(responses, requests)
    http = Object.new
    http.define_singleton_method(:read_timeout=) { |value| @read_timeout = value }
    http.define_singleton_method(:request) do |request, &block|
      requests << request
      if request.body_stream
        stream = request.body_stream
        stream.rewind if stream.respond_to?(:rewind)
        request.instance_variable_set(:@captured_body, stream.read)
        stream.rewind if stream.respond_to?(:rewind)
      end

      raw = responses.shift || raise("unexpected HTTP request")
      response = if raw.respond_to?(:read_body)
                   raw
                 else
                   bytes = raw.body.to_s.b
                   StreamingResponse.new(code: raw.code, chunks: [bytes],
                                         headers: { "content-length" => bytes.bytesize.to_s })
                 end
      block ? (block.call(response); response) : response
    end
    starter = lambda { |_host, _port, **_options, &block| block.call(http) }

    Net::HTTP.stub(:start, starter) { yield }
  end

  def with_download_response(response)
    http = Object.new
    http.define_singleton_method(:read_timeout=) { |value| @read_timeout = value }
    http.define_singleton_method(:request_get) { |_path, &block| block.call(response) }
    starter = lambda { |_host, _port, **_options, &block| block.call(http) }

    Net::HTTP.stub(:start, starter) { yield }
  end

  def test_paid_post_is_not_retried_after_an_ambiguous_server_error
    client = Client.new(token: "r8_test")
    requests = []
    failure = Struct.new(:code, :body).new("500", '{"detail":"internal server error"}')

    error = nil
    with_http_responses([failure], requests) do
      error = assert_raises(Client::TransientError) do
        client.create_model("owner/lora")
      end
    end

    assert_match(/500/, error.message)
    assert_equal ["POST"], requests.map(&:method),
                 "a 5xx may follow a successful paid create; do not blindly replay it"
  end

  def test_explicit_throttle_can_retry_post
    client = Client.new(token: "r8_test")
    client.define_singleton_method(:sleep) { |_seconds| }
    requests = []
    throttled = Struct.new(:code, :body).new("429", '{"detail":"Request was throttled; resets in ~1s."}')
    accepted = Struct.new(:code, :body).new("200", '{"id":"p1"}')

    result = with_http_responses([throttled, accepted], requests) do
      client.create_model("owner/lora")
    end

    assert_equal({ "id" => "p1" }, result)
    assert_equal 2, requests.length
  end

  def test_exhausted_budget_refusal_is_not_retried
    client = Client.new(token: "r8_test")
    requests = []
    exhausted = Struct.new(:code, :body).new("429", '{"detail":"Insufficient credit balance"}')

    Master::Io::QuotaCheck.stub(:trip!, ->(**_args) {}) do
      error = nil
      with_http_responses([exhausted], requests) do
        error = assert_raises(Client::ExhaustedError) do
          client.create_model("owner/lora")
        end
      end
      assert_match(/429/, error.message)
    end

    assert_equal 1, requests.length, "budget refusal cannot be fixed by a timed retry"
  end

  def test_model_pagination_refuses_an_external_cursor_before_sending_its_token
    client = Client.new(token: "replicate-test-secret")
    requests = []
    first = Struct.new(:code, :body).new(
      "200",
      JSON.generate("results" => [], "next" => "https://attacker.invalid/v1/models?cursor=secret"),
    )

    with_http_responses([first], requests) do
      error = assert_raises(ArgumentError) { client.models }
      assert_match(/outside the Replicate API origin/, error.message)
    end

    assert_equal 1, requests.size
    assert_equal "Token", requests.first["Authorization"].split(" ").first
    refute requests.any? { |request| request["Host"] == "attacker.invalid" }
  end

  def test_model_pagination_rejects_a_repeated_cursor_without_a_second_request
    client = Client.new(token: "replicate-test-secret")
    requests = []
    page = Struct.new(:code, :body).new(
      "200",
      JSON.generate("results" => [], "next" => "#{Client::BASE}/models"),
    )

    with_http_responses([page], requests) do
      error = assert_raises(ArgumentError) { client.models }
      assert_match(/repeated a cursor/, error.message)
    end

    assert_equal 1, requests.size
  end

  def test_model_pagination_accepts_only_the_models_cursor_on_the_api_origin
    client = Client.new(token: "replicate-test-secret")
    requests = []
    pages = [
      Struct.new(:code, :body).new(
        "200",
        JSON.generate(
          "results" => [{ "owner" => "first", "name" => "model" }],
          "next" => "https://api.replicate.com/v1/models?cursor=page-two",
        ),
      ),
      Struct.new(:code, :body).new(
        "200",
        JSON.generate("results" => [{ "owner" => "second", "name" => "model" }], "next" => nil),
      ),
    ]

    with_http_responses(pages, requests) { assert_equal 2, client.models.size }

    assert_equal 2, requests.size
    assert requests.all? { |request| request["Authorization"] == "Token replicate-test-secret" }
    assert requests.all? { |request| request.path.start_with?("/v1/models") }
  end

  def test_api_request_uses_explicit_connection_read_and_write_timeouts
    client = Client.new(token: "replicate-test-secret")
    request = nil
    response = StreamingResponse.new(chunks: ["{}"], headers: { "content-length" => "2" })
    http = Object.new
    http.define_singleton_method(:read_timeout=) { |value| @read_timeout = value }
    http.define_singleton_method(:request) do |value, &handler|
      request = value
      handler.call(response)
      response
    end

    Net::HTTP.stub(:start, lambda { |host, port, **options, &block|
      assert_equal "api.replicate.com", host
      assert_equal 443, port
      assert_equal true, options.fetch(:use_ssl)
      assert_equal Client::OPEN_TIMEOUT_SECONDS, options.fetch(:open_timeout)
      assert_operator options.fetch(:read_timeout), :<=, Client::READ_TIMEOUT_SECONDS
      assert_equal Client::WRITE_TIMEOUT_SECONDS, options.fetch(:write_timeout)
      block.call(http)
    }) do
      client.account_username
    end

    assert_equal "Token replicate-test-secret", request["Authorization"]
  end

  def test_replicate_token_files_must_be_private_regular_user_files
    Dir.mktmpdir do |directory|
      path = File.join(directory, "env")
      File.write(path, "REPLICATE_API_TOKEN=secret\n")
      File.chmod(0o600, path)
      assert Client.private_token_file?(path)
      assert_equal "REPLICATE_API_TOKEN=secret\n", Client.read_private_token_file(path)

      File.chmod(0o640, path)
      refute Client.private_token_file?(path)
      assert_nil Client.read_private_token_file(path)

      File.chmod(0o600, path)
      linked = File.join(directory, "hardlink")
      File.link(path, linked)
      refute Client.private_token_file?(path)
      assert_nil Client.read_private_token_file(path)
      File.unlink(linked)

      target = File.join(directory, "secret")
      File.rename(path, target)
      File.symlink(target, path)
      refute Client.private_token_file?(path)
      assert_nil Client.read_private_token_file(path)
    end
  end

  def test_replicate_token_file_read_refuses_oversized_input
    Dir.mktmpdir do |directory|
      path = File.join(directory, "env")
      File.binwrite(path, "x" * (Client::MAX_TOKEN_FILE_BYTES + 1))
      File.chmod(0o600, path)

      refute Client.private_token_file?(path)
      assert_nil Client.read_private_token_file(path)
    end
  end

  def test_provider_error_messages_keep_a_digest_but_not_the_response_body
    client = Client.new(token: "r8_test")
    body = '{"detail":"private upstream credential: token-do-not-log"}'
    response = Struct.new(:code, :body).new("500", body)
    requests = []

    error = with_http_responses([response], requests) do
      assert_raises(Client::TransientError) { client.create_model("owner/lora") }
    end

    refute_includes error.message, "private upstream credential"
    refute_includes error.message, "token-do-not-log"
    assert_includes error.message, "response_bytes=#{body.bytesize}"
    assert_includes error.message, Digest::SHA256.hexdigest(body)
    assert_equal 1, requests.length
  end

  def test_prediction_failure_redacts_provider_error_text
    client = Client.new(token: "r8_test")
    private_error = "upstream private prompt and credential"
    client.define_singleton_method(:get) do |_uri, deadline: nil|
      { "status" => "failed", "error" => private_error }
    end

    error = assert_raises(RuntimeError) { client.send(:wait_for, "prediction-1", timeout: 30) }

    refute_includes error.message, private_error
    assert_includes error.message, Digest::SHA256.hexdigest(private_error)
    assert_match(/provider error redacted/, error.message)
  end

  def test_retry_backoff_uses_equal_jitter_below_the_shared_exponential_cap
    client = Client.new(token: "r8_test")
    client.define_singleton_method(:rand) { 0.5 }
    waits = []
    client.define_singleton_method(:sleep) { |seconds| waits << seconds }
    requests = []
    failed = Struct.new(:code, :body).new("500", '{"detail":"temporary"}')
    accepted = Struct.new(:code, :body).new("200", '{"results":[{"name":"lora"}]}')

    result = with_http_responses([failed, failed, accepted], requests) do
      client.models(limit: 1)
    end

    assert_equal [{ "name" => "lora" }], result
    assert_equal [0.75, 1.5], waits
    assert_equal 3, requests.length
  end

  def test_download_is_streamed_capped_and_replaces_the_previous_file_atomically
    Dir.mktmpdir do |directory|
      target = File.join(directory, "audio.wav")
      File.binwrite(target, "previous audio")
      File.chmod(0o600, target)
      response = StreamingResponse.new(chunks: ["be", "at"],
                                       headers: { "content-length" => "4" })

      with_download_response(response) do
        assert_equal target, Client.new(token: "r8_test").download_url(
          "https://replicate.delivery/audio.wav", target, max_bytes: 4
        )
      end

      assert_equal "beat", File.binread(target)
      assert_equal 0o600, File.stat(target).mode & 0o777
      assert_equal 1, response.read_count
      assert_empty Dir.children(directory).grep(/replicate-download-/)
    end
  end

  def test_download_overflow_preserves_previous_output_and_removes_partial_file
    Dir.mktmpdir do |directory|
      target = File.join(directory, "weights.tar")
      File.binwrite(target, "previous weights")
      response = StreamingResponse.new(chunks: ["too large"], headers: { "content-length" => "2" })

      with_download_response(response) do
        error = assert_raises(ArgumentError) do
          Client.new(token: "r8_test").download_url(
            "https://replicate.delivery/weights.tar", target, max_bytes: 3
          )
        end
        assert_match(/download over 3 bytes/, error.message)
      end

      assert_equal "previous weights", File.binread(target)
      assert_empty Dir.children(directory).grep(/replicate-download-/)
    end
  end

  def test_download_refuses_untrusted_or_fragmented_urls_before_network
    client = Client.new(token: "r8_test")
    [
      "https://attacker.invalid/audio.wav",
      "https://replicate.delivery/audio.wav#fragment",
      "https://user:pass@replicate.delivery/audio.wav",
      "http://replicate.delivery/audio.wav",
    ].each do |url|
      assert_raises(ArgumentError, url) { client.download_url(url, "/tmp/not-written.wav") }
    end
    assert_raises(ArgumentError) do
      client.download_url("https://replicate.delivery/audio.wav", "/tmp/not-written.wav", max_bytes: 0)
    end
    assert_raises(ArgumentError) do
      client.download_url(
        "https://replicate.delivery/audio.wav", "/tmp/not-written.wav",
        max_bytes: Client::MAX_DOWNLOAD_BYTES + 1
      )
    end
  end

  def test_download_rejects_a_declared_oversize_response_before_streaming
    response = StreamingResponse.new(chunks: ["unused"],
                                     headers: { "content-length" => (Client::MAX_DOWNLOAD_BYTES + 1).to_s })
    with_download_response(response) do
      error = assert_raises(ArgumentError) do
        Client.new(token: "r8_test").download_url(
          "https://replicate.delivery/large.tar", "/tmp/not-written-large.tar"
        )
      end
      assert_match(/download over/, error.message)
    end
    assert_equal 0, response.read_count
  end

  def test_upload_streams_multipart_body_to_a_temporary_file_without_request_body_copy
    Dir.mktmpdir do |directory|
      source = File.join(directory, "photos.zip")
      File.binwrite(source, "archive bytes")
      requests = []
      accepted = StreamingResponse.new(
        chunks: ['{"urls":{"get":"https://replicate.delivery/files/uploaded.zip"}}']
      )

      url = with_http_responses([accepted], requests) do
        Client.new(token: "r8_test").upload_zip(source)
      end

      request = requests.fetch(0)
      captured = request.instance_variable_get(:@captured_body)
      assert_equal "https://replicate.delivery/files/uploaded.zip", url
      assert_nil request.body
      refute_nil request.body_stream
      assert_equal captured.bytesize.to_s, request["Content-Length"]
      assert_includes captured, "Content-Type: application/zip"
      assert_includes captured, "archive bytes"
      assert_includes captured, 'filename="photos.zip"'
    end
  end

  def test_upload_refuses_symlink_sources_before_sending_credentials
    Dir.mktmpdir do |directory|
      source = File.join(directory, "archive.zip")
      link = File.join(directory, "linked.zip")
      File.binwrite(source, "archive")
      File.symlink(source, link)
      requests = []

      error = assert_raises(ArgumentError) do
        Client.new(token: "r8_test").upload_zip(link)
      end

      assert_match(/regular non-symlink file/, error.message)
      assert_empty requests
    end
  end

  def test_streamed_upload_rewinds_the_body_for_an_explicit_throttle_retry
    Dir.mktmpdir do |directory|
      source = File.join(directory, "archive.zip")
      File.binwrite(source, "archive bytes")
      requests = []
      throttled = Struct.new(:code, :body).new("429", '{"detail":"Request was throttled; resets in ~1s."}')
      accepted = StreamingResponse.new(
        chunks: ['{"urls":{"get":"https://replicate.delivery/files/archive.zip"}}']
      )
      client = Client.new(token: "r8_test")
      client.define_singleton_method(:sleep) { |_seconds| }

      with_http_responses([throttled, accepted], requests) do
        client.upload_zip(source)
      end

      assert_equal 2, requests.length
      bodies = requests.map { |request| request.instance_variable_get(:@captured_body) }
      assert_equal bodies.first, bodies.last
    end
  end

  def test_api_response_byte_limit_rejects_declared_oversize_before_reading
    response = StreamingResponse.new(
      chunks: ["unused"],
      headers: { "content-length" => (Client::MAX_RESPONSE_BYTES + 1).to_s }
    )
    requests = []
    error = with_http_responses([response], requests) do
      assert_raises(Client::ResponseTooLarge) { Client.new(token: "r8_test").models(limit: 1) }
    end

    assert_match(/response exceeds/, error.message)
    assert_equal 0, response.read_count
    assert_equal 1, requests.length
  end

  def test_api_response_byte_limit_also_checks_streamed_bytes_without_a_length_header
    response = StreamingResponse.new(chunks: ["x" * (Client::MAX_RESPONSE_BYTES + 1)])
    requests = []
    error = with_http_responses([response], requests) do
      assert_raises(Client::ResponseTooLarge) { Client.new(token: "r8_test").models(limit: 1) }
    end

    assert_match(/response exceeds/, error.message)
    assert_equal 1, response.read_count
  end

  def test_prediction_polling_uses_one_monotonic_deadline
    client = Client.new(token: "r8_test")
    now = 10.0
    deadlines = []
    responses = [
      { "status" => "starting" },
      { "status" => "succeeded", "output" => "done" },
    ]
    client.define_singleton_method(:monotonic_now) { now }
    client.define_singleton_method(:get) do |_uri, deadline:|
      deadlines << deadline
      responses.shift
    end
    client.define_singleton_method(:sleep) { |seconds| now += seconds }

    assert_equal "done", client.send(:wait_for, "prediction-1", timeout: 5)
    assert_equal [15.0, 15.0], deadlines
    assert_equal 13.0, now
  end

  def test_prediction_deadline_cancels_instead_of_polling_forever
    client = Client.new(token: "r8_test")
    now = 0.0
    cancelled = []
    client.define_singleton_method(:monotonic_now) { now }
    client.define_singleton_method(:get) do |_uri, deadline:|
      raise Client::DeadlineExceeded if now >= deadline

      { "status" => "starting" }
    end
    client.define_singleton_method(:sleep) { |seconds| now += seconds }
    client.define_singleton_method(:cancel_prediction) { |id| cancelled << id }

    error = assert_raises(RuntimeError) do
      client.send(:wait_for, "prediction-2", timeout: 1)
    end

    assert_match(/prediction timeout after 1s/, error.message)
    assert_equal ["prediction-2"], cancelled
  end

  def test_invalid_prediction_and_training_deadlines_are_refused_before_network
    client = Client.new(token: "r8_test")
    requests = []
    client.define_singleton_method(:get) { |uri, **| requests << uri }
    client.define_singleton_method(:post) { |uri, _, **| requests << uri }

    [0, -1, Float::INFINITY, Float::NAN, "not-a-number"].each do |timeout|
      assert_raises(ArgumentError) { client.predict("owner/model", {}, timeout:) }
      assert_raises(ArgumentError) do
        client.train_lora("https://replicate.delivery/photos.zip", "owner/model", timeout:, wait: false)
      end
    end
    assert_empty requests
  end

  def test_api_deadline_is_enforced_before_opening_the_connection
    client = Client.new(token: "r8_test")
    requests = []
    http_error = assert_raises(Client::DeadlineExceeded) do
      client.send(:request, Net::HTTP::Get.new(URI("#{Client::BASE}/models")),
                  URI("#{Client::BASE}/models"), deadline: 0)
    end

    assert_match(/deadline exceeded/, http_error.message)
    assert_empty requests
  end

  def test_get_keeps_retrying_a_transient_server_error
    client = Client.new(token: "r8_test")
    client.define_singleton_method(:sleep) { |_seconds| }
    requests = []
    failed = Struct.new(:code, :body).new("500", '{"detail":"temporary server fault"}')
    accepted = Struct.new(:code, :body).new("200", '{"results":[{"name":"lora"}]}')

    result = with_http_responses([failed, accepted], requests) do
      client.models(limit: 1)
    end

    assert_equal([{ "name" => "lora" }], result)
    assert_equal 2, requests.length
  end
end
