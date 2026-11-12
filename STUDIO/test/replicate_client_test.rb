# frozen_string_literal: true

require_relative "minitest_helper"
require "tmpdir"
require_relative "../replicate/client"

class TestStudioReplicateClientPaths < Minitest::Test
  class StubClient < Studio::ReplicateClient
    attr_reader :requests

    def initialize
      @requests = []
      super(token: "test-token")
    end

    def get(uri)
      @requests << [:get, uri]
      {}
    end

    def post(uri, body, headers: {})
      @requests << [:post, uri, body, headers]
      { "id" => "prediction_123", "status" => "succeeded", "output" => "ok" }
    end
  end

  class SchemaClient < StubClient
    def get(uri)
      @requests << [:get, uri]
      properties = if uri.path.include?("/versions/")
                     { "prompt" => {}, "pinned_parameter" => {} }
                   else
                     { "prompt" => {}, "latest_parameter" => {} }
                   end
      schema = { "components" => { "schemas" => { "Input" => { "properties" => properties } } } }
      uri.path.include?("/versions/") ? { "openapi_schema" => schema } : { "latest_version" => { "openapi_schema" => schema } }
    end
  end

  class ReadTimeoutClient < StubClient
    def attempt_request(_request, _uri)
      raise Net::ReadTimeout, "simulated read timeout"
    end
  end

  class StatusClient < Studio::ReplicateClient
    def initialize(status)
      @status = status
      super(token: "test-token")
    end

    def get(_uri)
      raise Studio::ReplicateClient::APIError.new(@status, "provider response")
    end
  end

  class FakeResponse
    attr_reader :code

    def initialize(code: "200", headers: {}, chunks: [])
      @code = code
      @headers = headers.transform_keys(&:downcase)
      @chunks = chunks
    end

    def [](name)
      @headers[name.downcase]
    end

    def read_body
      @chunks.each { |chunk| yield chunk }
    end
  end

  class FakeHTTP
    def initialize(response)
      @response = response
    end

    def request_get(_path)
      yield @response
    end

    def request(_request)
      yield @response
    end
  end

  def with_http(response)
    start = lambda do |_host, _port, **options, &block|
      assert_equal true, options.fetch(:use_ssl)
      assert_equal Studio::ReplicateClient::WRITE_TIMEOUT_SECONDS, options.fetch(:write_timeout)
      block.call(FakeHTTP.new(response))
    end
    Net::HTTP.stub(:start, start) { yield }
  end

  def setup
    @client = StubClient.new
  end

  def test_pinned_model_reference_is_accepted_without_a_lookup
    version = "a" * 64

    assert_equal "ok", @client.predict("owner/model-name:#{version}", {})

    assert_equal 1, @client.requests.length
    method, uri, body, = @client.requests.fetch(0)
    assert_equal :post, method
    assert_equal "/v1/predictions", uri.path
    assert_equal version, body.fetch(:version)
  end

  def test_model_reference_cannot_escape_its_owner_and_model_segments
    [
      "owner/../account",
      "owner/model/extra",
      "owner/model%2fother",
      "owner",
      "../account/model"
    ].each do |reference|
      error = assert_raises(ArgumentError, reference) do
        @client.run(reference, {})
      end
      assert_match(/owner\/name/, error.message)
    end

    assert_empty @client.requests
  end

  def test_retry_exhaustion_preserves_the_original_network_exception
    client = ReadTimeoutClient.new
    uri = URI("https://api.replicate.com/v1/models")

    error = assert_raises(Net::ReadTimeout) do
      client.send(:request, Net::HTTP::Get.new(uri), uri, attempts: 1)
    end
    assert_match(/simulated read timeout/, error.message)
  end

  def test_model_lookup_only_treats_http_404_as_absent
    refute StatusClient.new(404).model_exists?("owner/model-name")

    error = assert_raises(Studio::ReplicateClient::APIError) do
      StatusClient.new(401).model_exists?("owner/model-name")
    end
    assert_equal 401, error.status
    assert_match(/provider response/, error.message)
  end

  def test_model_catalog_limit_rejects_invalid_values_before_network
    ["ten", "", "1.5", 0, -1, 1.5].each do |limit|
      assert_raises(ArgumentError) { @client.models(limit:) }
    end
    assert_empty @client.requests
  end

  def test_pinned_input_schema_uses_the_version_specific_endpoint
    version = "b" * 64
    client = SchemaClient.new

    assert_equal %w[prompt pinned_parameter], client.input_names("owner/model:#{version}")
    method, uri = client.requests.fetch(0)
    assert_equal :get, method
    assert_equal "/v1/models/owner/model/versions/#{version}", uri.path
  end

  def test_training_input_cannot_override_dataset_trigger_or_numeric_controls
    url = "https://files.replicate.delivery/photos.zip"
    %w[input_images trigger_word steps lora_rank].each do |key|
      error = assert_raises(ArgumentError) do
        @client.train_lora(url, "owner/model", wait: false, extra_input: { key => "override" })
      end
      assert_match(/cannot override/, error.message)
    end
    assert_empty @client.requests
  end

  def test_training_request_validates_url_trigger_steps_rank_and_extra_input_before_network
    url = "https://files.replicate.delivery/photos.zip"
    [
      -> { @client.train_lora("http://files.example.invalid/photos.zip", "owner/model", wait: false) },
      -> { @client.train_lora(url, "owner/model", trigger_word: "two words", wait: false) },
      -> { @client.train_lora(url, "owner/model", steps: 0, wait: false) },
      -> { @client.train_lora(url, "owner/model", lora_rank: "16", wait: false) },
      -> { @client.train_lora(url, "owner/model", extra_input: [], wait: false) }
    ].each { |call| assert_raises(ArgumentError, &call) }
    assert_empty @client.requests
  end

  def test_training_extra_input_is_merged_without_replacing_protected_fields
    url = "https://files.replicate.delivery/photos.zip"
    @client.train_lora(
      url, "owner/model", trigger_word: "SAMPLE", steps: 1_000, lora_rank: 16,
      wait: false, extra_input: { "seed" => 7 }
    )

    body = @client.requests.find { |request| request.first == :post }.fetch(2)
    assert_equal url, body.fetch(:input).fetch(:input_images)
    assert_equal "SAMPLE", body.fetch(:input).fetch(:trigger_word)
    assert_equal 1_000, body.fetch(:input).fetch(:steps)
    assert_equal 16, body.fetch(:input).fetch(:lora_rank)
    assert_equal 7, body.fetch(:input).fetch(:seed)
  end

  def test_training_destination_must_be_a_single_unpinned_model_reference
    error = assert_raises(ArgumentError) { @client.create_model("owner/model:version") }

    assert_match(/without a version/, error.message)
    assert_empty @client.requests
  end

  def test_training_and_prediction_resource_ids_cannot_be_paths
    assert_raises(ArgumentError) { @client.get_training("../account") }
    assert_nil @client.send(:cancel_prediction, "../account")
    assert_nil @client.send(:cancel_training, "../account")

    assert_empty @client.requests
  end

  def test_training_version_is_validated_before_a_create_request
    error = assert_raises(ArgumentError) do
      @client.train_lora("https://files.replicate.delivery/photos.zip", "owner/model",
                         wait: false, version: "../account")
    end

    assert_match(/trainer version/, error.message)
    assert_empty @client.requests, "invalid trainer version must fail before model lookup"
  end

  def test_api_origin_guard_rejects_dot_segments_and_escaped_paths
    [
      "https://api.replicate.com/v1/models/../account",
      "https://api.replicate.com/v1/models/%2e%2e/account",
      "https://api.replicate.com/v1/models/%2faccount",
      "http://api.replicate.com/v1/models",
      "mailto:operator@example.invalid"
    ].each do |url|
      assert_raises(ArgumentError, url) { @client.send(:api_uri, url) }
    end
  end

  def test_download_is_atomic_and_streamed_under_the_declared_byte_cap
    Dir.mktmpdir do |directory|
      target = File.join(directory, "audio.wav")
      File.write(target, "old render")
      File.chmod(0o600, target)
      response = FakeResponse.new(headers: { "content-length" => "4" }, chunks: ["be", "at"])

      with_http(response) do
        assert_equal target, @client.download_url("https://replicate.delivery/audio.wav", target, max_bytes: 4)
      end

      assert_equal "beat", File.binread(target)
      assert_equal 0o600, File.stat(target).mode & 0o777
      assert_empty Dir.children(directory).grep(/replicate-download-/)
    end
  end

  def test_download_stream_overflow_preserves_previous_output_and_cleans_temporary_file
    Dir.mktmpdir do |directory|
      target = File.join(directory, "weights.tar")
      File.binwrite(target, "previous weights")
      response = FakeResponse.new(headers: { "content-length" => "2" }, chunks: ["too large"])

      with_http(response) do
        error = assert_raises(RuntimeError) do
          @client.download_url("https://replicate.delivery/weights.tar", target, max_bytes: 3)
        end
        assert_match(/download over 3 bytes/, error.message)
      end

      assert_equal "previous weights", File.binread(target)
      assert_empty Dir.children(directory).grep(/replicate-download-/)
    end
  end

  def test_download_rejects_untrusted_hosts_and_invalid_limits_before_network
    assert_raises(ArgumentError) do
      @client.download_url("https://files.example.invalid/archive.zip", "/tmp/not-written.zip")
    end
    assert_raises(ArgumentError) do
      @client.download_url("https://replicate.delivery/archive.zip", "/tmp/not-written.zip", max_bytes: 0)
    end
  end

  def test_api_json_response_is_rejected_before_reading_past_the_cap
    uri = URI("https://api.replicate.com/v1/models")
    response = FakeResponse.new(headers: {
      "content-length" => (Studio::ReplicateClient::MAX_RESPONSE_BYTES + 1).to_s
    })
    with_http(response) do
      error = assert_raises(ArgumentError) { @client.send(:attempt_request, Net::HTTP::Get.new(uri), uri) }
      assert_match(/response exceeds/, error.message)
    end
  end

  def test_operation_deadlines_preserve_integer_seconds
    assert_equal 600, @client.send(:operation_timeout!, 600, "prediction timeout")
    assert_equal 1.5, @client.send(:operation_timeout!, 1.5, "prediction timeout")
  end

  def test_prediction_and_training_deadlines_must_be_finite_and_positive_before_requests
    [0, -1, Float::INFINITY, Float::NAN, "not-a-number"].each do |timeout|
      assert_raises(ArgumentError) do
        @client.run("owner/model", {}, timeout:)
      end
      assert_raises(ArgumentError) do
        @client.train_lora("https://files.replicate.delivery/photos.zip", "owner/model",
                           timeout:, wait: false)
      end
    end
    assert_empty @client.requests
  end

  def test_upload_requires_a_readable_regular_file
    Dir.mktmpdir do |directory|
      source = File.join(directory, "notes.txt")
      File.write(source, "not an image")
      assert_raises(ArgumentError) { @client.upload_file(source) }
      assert_raises(ArgumentError) { @client.upload_zip(File.join(directory, "missing.zip")) }
      assert_empty @client.requests
    end
  end
end
