# frozen_string_literal: true

require_relative "minitest_helper"
require "tmpdir"
require_relative "../client"

# Request-construction tests use a synthetic subject; the actual gate has its
# own dedicated regression suite.
Studio::Lora::Consent.define_singleton_method(:require!) { |**| { "valid" => true } }

class TestStudioReplicateClientPaths < Minitest::Test
  class StubClient < Studio::ReplicateClient
    attr_reader :requests

    def initialize
      @requests = []
      super(token: "test-token")
    end

    # These tests exercise request construction, not human permissions or
    # subject file loading; consent and trigger are isolated test seams.
    def train_lora(*arguments, **options)
      options[:subject] ||= "probe"
      super(*arguments, **options)
    end

    def training_trigger_for_subject(_directory, supplied)
      send(:training_trigger!, supplied)
    end

    def get(uri)
      @requests << [:get, uri]
      properties = {
        "input_images" => {},
        "trigger_word" => {},
        "lora_type" => {},
        "training_steps" => {},
        "seed" => {}
      }
      schema = {
        "properties" => properties,
        "required" => []
      }
      if uri.path.include?("/versions/")
        { "openapi_schema" => { "components" => { "schemas" => { "Input" => schema } } } }
      else
        { "visibility" => "private", "latest_version" => {
          "id" => "c" * 64,
          "openapi_schema" => { "components" => { "schemas" => { "Input" => schema } } }
        } }
      end
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
      input = { "properties" => properties, "required" => ["prompt"] }
      schema = { "components" => { "schemas" => { "Input" => input } } }
      uri.path.include?("/versions/") ? { "openapi_schema" => schema } :
        { "latest_version" => { "id" => "d" * 64, "openapi_schema" => schema } }
    end
  end

  class H3VideoClient < StubClient
    def get(uri)
      @requests << [:get, uri]
      schema = {
        "properties" => { "prompt" => {}, "first_frame_image" => {}, "duration" => {} },
        "required" => %w[prompt first_frame_image duration]
      }
      wrapped = { "components" => { "schemas" => { "Input" => schema } } }
      uri.path.include?("/versions/") ? { "openapi_schema" => wrapped } :
        { "latest_version" => { "id" => "e" * 64, "openapi_schema" => wrapped } }
    end
  end

  class MissingTrainerFieldClient < StubClient
    def get(uri)
      @requests << [:get, uri]
      schema = {
        "properties" => { "input_images" => {}, "prompt" => {} },
        "required" => ["input_images"]
      }
      { "openapi_schema" => { "components" => { "schemas" => { "Input" => schema } } } }
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
    attr_accessor :ipaddr, :use_ssl, :open_timeout, :read_timeout, :write_timeout
    attr_reader :host, :port, :proxy_address

    def initialize(response, host:, port:, proxy_address:)
      @response = response
      @host = host
      @port = port
      @proxy_address = proxy_address
    end

    def start
      yield self
    end

    def request_get(_path)
      yield @response
    end

    def request(_request)
      yield @response
    end
  end

  def with_http(response, timeout: nil)
    http = nil
    constructor = lambda do |host, port, proxy_address|
      assert_equal 443, port
      assert_nil proxy_address, "environment proxy must not bypass the IP pin"
      http = FakeHTTP.new(response, host:, port:, proxy_address:)
    end
    resolver = ->(_host) { ["93.184.216.34"] }
    Studio::ReplicateClient.stub(:resolve_download_addresses, resolver) do
      Net::HTTP.stub(:new, constructor) do
        yield
      end
    end
    expected_write_timeout = timeout ? [Studio::ReplicateClient::WRITE_TIMEOUT_SECONDS, timeout].min :
      Studio::ReplicateClient::WRITE_TIMEOUT_SECONDS
    assert_equal expected_write_timeout, http.write_timeout
    if timeout
      assert_equal [Studio::ReplicateClient::OPEN_TIMEOUT_SECONDS, timeout].min, http.open_timeout
      assert_equal [Studio::ReplicateClient::READ_TIMEOUT_SECONDS, timeout].min, http.read_timeout
    end
    assert_equal "93.184.216.34", http.ipaddr
    assert_equal true, http.use_ssl
  end

  def setup
    @client = StubClient.new
  end

  def test_h3_video_prediction_reserves_the_estimate_before_posting
    models = Studio::ReplicateClient::Models
    models.reset_video_budget!
    client = H3VideoClient.new

    assert_equal "ok", client.predict(
      "minimax/h3-highspeed",
      { prompt: "a quiet harbour", first_frame_image: "https://example.test/frame.jpg", duration: 10 }
    )
    expected = models.video_cost_usd("minimax/h3-highspeed", { "duration" => 10 }, today: Date.today)
    assert_in_delta expected, models.video_budget_spent, 0.001
    assert_equal %i[get get post], client.requests.map(&:first)
  ensure
    models.reset_video_budget!
  end

  def test_prediction_receipt_separates_reserved_estimate_from_actual_billing
    models = Studio::ReplicateClient::Models
    models.reset_video_budget!
    client = H3VideoClient.new

    result = client.predict_with_receipt(
      "minimax/h3-highspeed",
      { prompt: "a quiet harbour", first_frame_image: "https://example.test/frame.jpg", duration: 10 }
    )
    expected = models.video_cost_usd("minimax/h3-highspeed", { "duration" => 10 }, today: Date.today)
    receipt = result.fetch("receipt")

    assert_equal "ok", result.fetch("output")
    assert_equal "studio.replicate.prediction.v1", receipt.fetch("schema")
    assert_equal "prediction_123", receipt.fetch("prediction_id")
    assert_equal "succeeded", receipt.fetch("status")
    assert_in_delta expected, receipt.fetch("estimated_cost_usd"), 0.001
    assert_nil receipt.fetch("actual_cost_usd")
    assert_equal "NOT_REPORTED_BY_PREDICTION_API", receipt.fetch("actual_cost_status")
    assert_equal expected, models.video_budget_spent
    assert_equal %i[get get post], client.requests.map(&:first)
  ensure
    models.reset_video_budget!
  end

  def test_pinned_model_reference_uses_its_version_schema_before_prediction
    version = "a" * 64

    assert_equal "ok", @client.predict("owner/model-name:#{version}", {})

    assert_equal %i[get post], @client.requests.map(&:first)
    schema_method, schema_uri = @client.requests.fetch(0)
    assert_equal :get, schema_method
    assert_equal "/v1/models/owner/model-name/versions/#{version}", schema_uri.path
    method, uri, body, = @client.requests.fetch(1)
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

  def test_model_catalog_accepts_positive_integer_string_limits
    assert_empty @client.models(limit: "10")
    assert_equal [:get], @client.requests.map(&:first)
  end

  def test_model_catalog_limit_rejects_invalid_values_before_network
    ["ten", "", "1.5", 0, -1, 1.5].each do |limit|
      assert_raises(ArgumentError) { @client.models(limit:) }
    end
    assert_empty @client.requests
  end

  def test_predictions_reject_unknown_fields_before_submission
    version = "c" * 64
    error = assert_raises(ArgumentError) do
      @client.run("owner/model:#{version}", { "prompt" => "ok", "not_a_field" => true })
    end

    assert_match(/unsupported inputs/, error.message)
    assert_equal [:get], @client.requests.map(&:first)
    assert_match(%r{/versions/#{version}\z}, @client.requests.first.fetch(1).path)
  end

  def test_predictions_require_schema_mandatory_fields_before_submission
    client = SchemaClient.new
    version = "d" * 64
    error = assert_raises(ArgumentError) do
      client.run("owner/model:#{version}", {})
    end

    assert_match(/missing required inputs.*prompt/, error.message)
    assert_equal [:get], client.requests.map(&:first)
  end

  def test_pinned_input_schema_uses_the_version_specific_endpoint
    version = "b" * 64
    client = SchemaClient.new

    assert_equal %w[prompt pinned_parameter], client.input_names("owner/model:#{version}")
    method, uri = client.requests.fetch(0)
    assert_equal :get, method
    assert_equal "/v1/models/owner/model/versions/#{version}", uri.path
  end

  def test_existing_public_training_destination_is_refused
    public_client = Class.new(StubClient) do
      def model_exists?(_model_id) = true
      def model_visibility(_model_id) = "public"
    end.new

    error = assert_raises(ArgumentError) { public_client.ensure_private_model!("owner/model") }
    assert_match(/is public/, error.message)
    assert_empty public_client.requests
  end

  def test_missing_training_destination_is_created_private
    client = StubClient.new
    client.stub(:model_exists?, false) do
      client.ensure_private_model!("owner/private-model")
    end

    request = client.requests.find { |row| row.first == :post }
    assert_equal "private", request.fetch(2).fetch(:visibility)
  end

  def test_fast_flux_training_schema_is_checked_before_destination_model_creation
    client = MissingTrainerFieldClient.new
    error = assert_raises(ArgumentError) do
      client.train_lora(
        "https://files.replicate.delivery/photos.zip", "owner/model",
        trigger_word: "SAMPLE", wait: false
      )
    end

    assert_match(/unsupported inputs.*trigger_word/, error.message)
    assert_equal [:get], client.requests.map(&:first)
    assert_match(%r{/versions/}, client.requests.first.fetch(1).path)
  end

  def test_training_defaults_come_from_the_shared_fast_flux_standard
    url = "https://files.replicate.delivery/photos.zip"
    @client.train_lora(url, "owner/model", trigger_word: "SAMPLE", wait: false)

    request = @client.requests.find { |item| item.first == :post }
    input = request.fetch(2).fetch(:input)
    standard = Studio::ReplicateClient::TRAINING_STANDARDS.fetch("replicate")
    assert_equal url, input.fetch(:input_images)
    assert_equal "SAMPLE", input.fetch(:trigger_word)
    assert_equal standard.fetch("lora_type"), input.fetch(:lora_type)
    assert_equal standard.fetch("training_steps"), input.fetch(:training_steps)
    assert_equal standard.fetch("seed"), input.fetch(:seed)
  end

  def test_trainer_constants_match_the_shared_fast_flux_standard
    standard = Studio::ReplicateClient::TRAINING_STANDARDS.fetch("replicate")
    assert_equal standard.fetch("trainer"), Studio::ReplicateClient::LORA_TRAINER
    assert_equal standard.fetch("version"), Studio::ReplicateClient::LORA_TRAINER_VERSION
  end

  def test_callers_cannot_override_shared_training_settings
    url = "https://files.replicate.delivery/photos.zip"
    invalid = [
      -> { @client.train_lora(url, "owner/model", trigger_word: "SAMPLE", training_steps: 1200, wait: false) },
      -> { @client.train_lora(url, "owner/model", trigger_word: "SAMPLE", lora_type: "style", wait: false) },
      -> { @client.train_lora(url, "owner/model", trigger_word: "SAMPLE", seed: 43, wait: false) },
    ]
    invalid.each { |call| assert_raises(ArgumentError, &call) }
    assert_empty @client.requests
  end

  def test_training_request_validates_url_trigger_type_steps_and_seed_before_network
    url = "https://files.replicate.delivery/photos.zip"
    invalid = [
      -> { @client.train_lora("http://files.example.invalid/photos.zip", "owner/model", trigger_word: "SAMPLE", wait: false) },
      -> { @client.train_lora(url, "owner/model", trigger_word: "two words", wait: false) },
      -> { @client.train_lora(url, "owner/model", trigger_word: "SAMPLE", lora_type: "unknown", wait: false) },
      -> { @client.train_lora(url, "owner/model", trigger_word: "SAMPLE", training_steps: 0, wait: false) },
      -> { @client.train_lora(url, "owner/model", trigger_word: "SAMPLE", seed: -1, wait: false) },
    ]
    invalid.each { |call| assert_raises(ArgumentError, &call) }
    assert_empty @client.requests
  end

  def test_training_destination_must_be_a_single_unpinned_model_reference
    error = assert_raises(ArgumentError) { @client.create_model("owner/model:version") }

    assert_match(/without a version/, error.message)
    assert_empty @client.requests
  end

  def test_training_timeout_returns_terminal_cancellation_metrics_after_provider_confirmation
    client, cancellations = timeout_client("canceled", metrics: { "predict_time" => 80.0 })

    result = client.wait_for_training("training_123", timeout: 1)

    assert_equal "canceled", result.fetch("status")
    assert_equal true, result.fetch("client_cancel_confirmed")
    assert_equal 80.0, result.dig("metrics", "predict_time")
    assert_equal ["training_123"], cancellations
  end

  def test_training_timeout_does_not_claim_cancellation_when_provider_is_still_running
    client, cancellations = timeout_client("processing")

    error = assert_raises(RuntimeError) { client.wait_for_training("training_123", timeout: 1) }

    assert_includes error.message, "cancellation NOT confirmed"
    assert_includes error.message, "processing"
    assert_equal ["training_123"], cancellations
  end

  def test_failed_training_returns_terminal_compute_metrics_for_spend_accounting
    client = StubClient.new
    client.define_singleton_method(:get_training) do |_id|
      { "id" => "training_123", "status" => "failed", "metrics" => { "predict_time" => 35.0 } }
    end

    result = client.wait_for_training("training_123", timeout: 1)

    assert_equal "failed", result.fetch("status")
    assert_equal 35.0, result.dig("metrics", "predict_time")
  end

  def test_training_completion_racing_the_timeout_returns_provider_metrics
    client, cancellations = timeout_client("succeeded", metrics: { "predict_time" => 120.0 })

    result = client.wait_for_training("training_123", timeout: 1)

    assert_equal "succeeded", result.fetch("status")
    assert_equal 120.0, result.dig("metrics", "predict_time")
    assert_equal ["training_123"], cancellations
  end

  def timeout_client(final_status, metrics: {})
    client = StubClient.new
    responses = [
      { "id" => "training_123", "status" => "processing" },
      { "id" => "training_123", "status" => final_status, "metrics" => metrics }
    ]
    cancellations = []
    ticks = [0.0, 2.0]
    client.define_singleton_method(:get_training) { |_id| responses.shift || responses.last }
    client.define_singleton_method(:cancel_training) { |id| cancellations << id; nil }
    client.define_singleton_method(:monotonic_now) { ticks.shift || 2.0 }
    [client, cancellations]
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
                         trigger_word: "SAMPLE", wait: false, version: "../account")
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

  def test_download_dns_accepts_public_ipv6_only_answers
    addresses = ["2001:4860:4860::8888"]

    Studio::ReplicateClient.stub(:resolve_download_addresses, ->(_host) { addresses }) do
      assert_equal addresses.fetch(0), Studio::ReplicateClient.public_download_address!("replicate.delivery")
    end
  end

  def test_download_dns_rejects_private_ipv6_and_public_then_private_answers
    [
      ["fd00::1"],
      ["93.184.216.34", "fd00::1"]
    ].each do |addresses|
      Studio::ReplicateClient.stub(:resolve_download_addresses, ->(_host) { addresses }) do
        assert_raises(ArgumentError) do
          Studio::ReplicateClient.public_download_address!("replicate.delivery")
        end
      end
    end
  end

  def test_download_rejects_redirects_without_following_the_location
    Dir.mktmpdir do |directory|
      target = File.join(directory, "audio.wav")
      File.binwrite(target, "previous output")
      response = FakeResponse.new(
        code: "302",
        headers: { "location" => "https://127.0.0.1/private", "content-length" => "0" }
      )

      with_http(response) do
        error = assert_raises(RuntimeError) do
          @client.download_url("https://replicate.delivery/audio.wav", target)
        end
        assert_match(/download failed 302/, error.message)
      end

      assert_equal "previous output", File.binread(target)
      assert_empty Dir.children(directory).grep(/replicate-download-/)
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

  def test_interrupted_download_never_publishes_a_partial_file
    Dir.mktmpdir do |directory|
      target = File.join(directory, "new-audio.wav")
      response = FakeResponse.new(headers: { "content-length" => "2" }, chunks: ["be", "at"])

      with_http(response) do
        error = assert_raises(RuntimeError) do
          @client.download_url("https://replicate.delivery/audio.wav", target, max_bytes: 3)
        end
        assert_match(/download over 3 bytes/, error.message)
      end

      refute File.exist?(target)
      assert_empty Dir.children(directory)
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

  def test_download_refuses_symlink_targets_before_network
    Dir.mktmpdir do |directory|
      original = File.join(directory, "original.wav")
      target = File.join(directory, "download.wav")
      File.write(original, "keep original")
      File.symlink(original, target)

      Net::HTTP.stub(:new, ->(*_args, **_options) { flunk "symlink target must be refused before network" }) do
        error = assert_raises(ArgumentError) do
          @client.download_url("https://replicate.delivery/audio.wav", target)
        end
        assert_match(/symlink download target/, error.message)
      end

      assert File.symlink?(target)
      assert_equal "keep original", File.read(original)
    end
  end

  def test_download_refuses_a_directory_as_its_target_before_network
    Dir.mktmpdir do |directory|
      target = File.join(directory, "download")
      Dir.mkdir(target)

      Net::HTTP.stub(:new, ->(*_args, **_options) { flunk "directory target must be refused before network" }) do
        error = assert_raises(ArgumentError) do
          @client.download_url("https://replicate.delivery/audio.wav", target)
        end
        assert_match(/not a regular file/, error.message)
      end
    end
  end

  def test_download_deadline_must_be_positive_and_finite_before_network
    Dir.mktmpdir do |directory|
      target = File.join(directory, "download.wav")
      Net::HTTP.stub(:new, ->(*_args, **_options) { flunk "invalid deadline must be refused before network" }) do
        [0, -1, Float::INFINITY, Float::NAN, "not-a-number"].each do |timeout|
          assert_raises(ArgumentError) do
            @client.download_url("https://replicate.delivery/audio.wav", target, timeout:)
          end
        end
      end
    end
  end

  def test_download_enforces_total_monotonic_deadline_and_preserves_previous_output
    Dir.mktmpdir do |directory|
      target = File.join(directory, "audio.wav")
      File.write(target, "previous output")
      response = FakeResponse.new(headers: { "content-length" => "4" }, chunks: ["be", "at"])
      times = [0.0, 2.0]

      @client.stub(:monotonic_now, -> { times.shift || 2.0 }) do
        with_http(response, timeout: 1) do
          error = assert_raises(IOError) do
            @client.download_url("https://replicate.delivery/audio.wav", target, timeout: 1)
          end
          assert_match(/monotonic deadline/, error.message)
        end
      end

      assert_equal "previous output", File.read(target)
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

  def test_download_refuses_mixed_public_and_private_dns_answers
    Studio::ReplicateClient.stub(
      :resolve_download_addresses, ->(_host) { ["93.184.216.34", "127.0.0.1"] }
    ) do
      error = assert_raises(ArgumentError) do
        Studio::ReplicateClient.public_download_address!("replicate.delivery")
      end
      assert_match(/non-public address/, error.message)
    end
  end

  def test_download_accepts_multiple_public_answers_and_pins_one
    Studio::ReplicateClient.stub(
      :resolve_download_addresses, ->(_host) { ["93.184.216.34", "8.8.8.8"] }
    ) do
      assert_equal "93.184.216.34",
                   Studio::ReplicateClient.public_download_address!("replicate.delivery")
    end
  end

  def test_download_blocks_mapped_nat64_6to4_teredo_and_non_global_ipv6
    %w[
      ::ffff:127.0.0.1 64:ff9b::a00:1 64:ff9b:1::a00:1
      2002:0a00:0001::1 2001:0::1 ::a00:1 fc00::1 4000::1 3fff::1 192.31.196.1 192.52.193.1 192.175.48.1 2620:4f:8000::1
    ].each do |address|
      assert Studio::ReplicateClient.blocked_download_ip?(IPAddr.new(address)), "#{address} must be blocked"
    end
    refute Studio::ReplicateClient.blocked_download_ip?(IPAddr.new("2606:4700:4700::1111"))
  end

  def test_download_dns_labels_reject_invalid_characters
    refute Studio::ReplicateClient.valid_download_hostname?("bad_name.replicate.delivery")
    refute Studio::ReplicateClient.valid_download_hostname?("-bad.replicate.delivery")
    refute Studio::ReplicateClient.valid_download_hostname?("bad-.replicate.delivery")
    refute Studio::ReplicateClient.valid_download_hostname?("replicate")
    assert Studio::ReplicateClient.valid_download_hostname?("replicate.delivery")
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

  def test_replicate_api_request_has_a_total_deadline
    uri = URI("https://api.replicate.com/v1/models")
    http = FakeHTTP.new(
      FakeResponse.new, host: "api.replicate.com", port: 443, proxy_address: nil
    )
    http.define_singleton_method(:request) { |_request| sleep 0.05 }

    Studio::ReplicateClient.stub(:resolve_download_addresses, ["93.184.216.34"]) do
      Net::HTTP.stub(:new, ->(*_args) { http }) do
        error = assert_raises(Studio::ReplicateClient::DeadlineExceeded) do
          @client.send(:attempt_request, Net::HTTP::Get.new(uri), uri, timeout: 0.01)
        end
        assert_match(/total deadline/, error.message)
      end
    end
  end

  def test_replicate_api_deadline_is_bounded_before_dns_resolution
    uri = URI("https://api.replicate.com/v1/models")
    resolved = false
    resolver = ->(_host) { resolved = true; ["93.184.216.34"] }

    Studio::ReplicateClient.stub(:resolve_download_addresses, resolver) do
      assert_raises(ArgumentError) do
        @client.send(:attempt_request, Net::HTTP::Get.new(uri), uri,
                     timeout: Studio::ReplicateClient::MAX_API_TOTAL_TIMEOUT_SECONDS + 1)
      end
    end
    refute resolved, "an invalid time budget must be rejected before DNS resolution"
  end

  def test_replicate_api_transport_does_not_follow_redirects
    uri = URI("https://api.replicate.com/v1/models")
    response = FakeResponse.new(code: "302", headers: { "location" => "https://127.0.0.1/private" })
    requests = 0
    http = FakeHTTP.new(response, host: "api.replicate.com", port: 443, proxy_address: nil)
    http.define_singleton_method(:request) do |_request, &block|
      requests += 1
      block.call(response)
    end

    Studio::ReplicateClient.stub(:resolve_download_addresses, ["93.184.216.34"]) do
      Net::HTTP.stub(:new, ->(*_args) { http }) do
        assert_raises(Studio::ReplicateClient::APIError) do
          @client.send(:attempt_request, Net::HTTP::Get.new(uri), uri)
        end
      end
    end
    assert_equal 1, requests
  end

  def test_replicate_api_refuses_transport_without_ip_pinning
    uri = URI("https://api.replicate.com/v1/models")
    http = Object.new
    def http.use_ssl=(_value); end
    def http.open_timeout=(_value); end
    def http.read_timeout=(_value); end
    def http.write_timeout=(_value); end

    Studio::ReplicateClient.stub(:resolve_download_addresses, ["93.184.216.34"]) do
      Net::HTTP.stub(:new, ->(*_args) { http }) do
        error = assert_raises(SocketError) do
          @client.send(:attempt_request, Net::HTTP::Get.new(uri), uri)
        end
        assert_match(/cannot pin/, error.message)
      end
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

  def test_training_zip_upload_requires_private_owner_only_file
    Dir.mktmpdir do |directory|
      path = File.join(directory, "training.zip")
      File.write(path, "zip", mode: "w", perm: 0o644)
      error = assert_raises(ArgumentError) { @client.upload_zip(path, subject: "probe") }
      assert_match(/owner-only/, error.message)
      assert_empty @client.requests

      File.chmod(0o600, path)
      assert_equal path, @client.send(:validate_private_training_zip!, path)
    end
  end

  def test_upload_requires_a_readable_regular_file
    Dir.mktmpdir do |directory|
      source = File.join(directory, "notes.txt")
      File.write(source, "not an image")
      assert_raises(ArgumentError) { @client.upload_file(source, subject: "probe") }
      assert_raises(ArgumentError) { @client.upload_zip(File.join(directory, "missing.zip"), subject: "probe") }
      assert_empty @client.requests
    end
  end
end
