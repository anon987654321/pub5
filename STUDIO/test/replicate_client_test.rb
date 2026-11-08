# frozen_string_literal: true

require_relative "minitest_helper"
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
    assert_equal [:get], @client.requests.map(&:first)
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
