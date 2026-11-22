# frozen_string_literal: true

require_relative "test_helper"

# SsrfGuard is the only thing standing between a prompt-injection payload and the runtime's own internal network, and
# its whole contract is a list of ranges — the cheapest possible thing to get
# wrong silently and the cheapest possible thing to pin.
class SsrfGuardTest < Minitest::Test
  Guard = Master::Io::SsrfGuard

  def test_blocks_loopback_link_local_and_private
    %w[127.0.0.1 ::1 169.254.169.254 10.0.0.1 172.16.4.5 192.168.1.1 fe80::1].each do |address|
      assert Guard.blocked_ip?(IPAddr.new(address)), "#{address} must be blocked"
    end
  end

  def test_blocks_ipv4_mapped_loopback_and_metadata
    assert Guard.blocked_ip?(IPAddr.new("::ffff:127.0.0.1")), "mapped loopback must be blocked"
    assert Guard.blocked_ip?(IPAddr.new("::ffff:169.254.169.254")), "mapped metadata must be blocked"
  end

  # The cloud metadata endpoint is the reason this guard exists; keep it named.
  def test_blocks_the_cloud_metadata_address
    assert Guard.blocked_ip?(IPAddr.new("169.254.169.254"))
  end

  def test_blocks_the_declared_reserved_ranges
    Guard::RESERVED_RANGES.each do |range|
      assert Guard.blocked_ip?(range.to_range.first), "#{range} should be blocked at its first address"
    end
  end

  def test_allows_ordinary_public_addresses
    %w[1.1.1.1 93.184.216.34 2606:4700:4700::1111].each do |address|
      refute Guard.blocked_ip?(IPAddr.new(address)), "#{address} should be allowed"
    end
  end

  # An unparseable address must fail closed, not open.
  def test_an_unusable_argument_is_blocked
    assert Guard.blocked_ip?(Object.new)
  end

  def test_rejects_non_http_and_hostless_uris
    refute Guard.safe_uri?(URI.parse("file:///etc/passwd"))
    refute Guard.safe_uri?(URI.parse("ftp://example.com/x"))
    refute Guard.safe_uri?("http://example.com")
  end

  def test_rejects_localhost_by_name_without_resolving
    refute Guard.safe_uri?(URI.parse("http://localhost/admin"))
    refute Guard.safe_uri?(URI.parse("http://LOCALHOST:8080/admin"))
  end

  def test_rejects_a_hostname_that_resolves_to_a_private_address
    Guard.stub(:resolve_addresses, ["10.1.2.3"]) do
      refute Guard.safe_uri?(URI.parse("http://internal.example.com/"))
    end
  end

  # A name with one public and one private answer is a rebinding-shaped input;
  # `all?` has to mean all.
  def test_rejects_a_mixed_answer_set
    Guard.stub(:resolve_addresses, ["1.1.1.1", "127.0.0.1"]) do
      refute Guard.safe_uri?(URI.parse("http://mixed.example.com/"))
    end
  end

  def test_accepts_a_hostname_that_resolves_publicly
    Guard.stub(:resolve_addresses, ["93.184.216.34"]) do
      assert Guard.safe_uri?(URI.parse("http://example.com/"))
    end
  end

  def test_rejects_a_name_that_does_not_resolve
    Guard.stub(:resolve_addresses, []) do
      refute Guard.safe_uri?(URI.parse("http://nx.example.invalid/"))
    end
  end

  def test_rejects_dns_names_over_protocol_limits_before_resolving
    refute Guard.valid_resolver_host?("#{"a" * 64}.example")
    long_name = Array.new(4, "a" * 63).join(".")
    refute Guard.valid_resolver_host?(long_name)
    called = false

    Guard.stub(:resolve_addresses, ->(_host) { called = true; ["1.1.1.1"] }) do
      refute Guard.safe_uri?(URI.parse("http://#{long_name}/"))
    end
    refute called, "overlong DNS name must be rejected before resolving"
  end

  # The socket goes to the address the check approved, so a second DNS answer
  # at connect time cannot move it; the hostname still carries TLS.
  def test_blocks_ipv6_outside_global_unicast
    %w[4000::1 5f00::1 3fff::1 2001:0::1].each do |address|
      assert Guard.blocked_ip?(IPAddr.new(address)), "#{address} is not a global unicast target"
    end
  end

  def test_rejects_nonstandard_http_ports_before_dns
    called = false
    Guard.stub(:resolve_addresses, ->(_host) { called = true; ["93.184.216.34"] }) do
      refute Guard.safe_uri?(URI("https://example.com:8443/"))
      refute Guard.safe_uri?(URI("http://example.com:8080/"))
    end
    refute called, "nonstandard ports must be rejected before DNS resolution"
    Guard.stub(:resolve_addresses, ["93.184.216.34"]) do
      assert Guard.safe_uri?(URI("http://example.com/"))
    end
  end

  def test_requires_a_fully_qualified_dns_name
    called = false
    Guard.stub(:resolve_addresses, ->(_host) { called = true; ["93.184.216.34"] }) do
      refute Guard.safe_uri?(URI("http://buildhost/"))
    end
    refute called, "single-label names must not use resolver search domains"
  end

  def test_http_for_refuses_an_untrusted_pinned_address
    assert_raises(SocketError) do
      Guard.http_for(URI("https://example.com/"), "169.254.169.254")
    end
  end

  def test_blocks_ipv4_compatible_ipv6_and_unique_local_ipv6
    %w[::a00:1 fc00::1 fd00::1].each do |address|
      assert Guard.blocked_ip?(IPAddr.new(address)), "#{address} must be blocked"
    end
  end

  def test_rejects_url_credentials_and_fragments
    refute Guard.safe_uri?(URI.parse("https://user:pass@example.com/"))
    refute Guard.safe_uri?(URI.parse("https://example.com/path#fragment"))
  end

  def test_rejects_reserved_local_dns_suffixes_before_resolution
    called = false
    %w[printer.local service.internal laptop.home.arpa host.onion name.localhost].each do |host|
      Guard.stub(:resolve_addresses, ->(_name) { called = true; ["1.1.1.1"] }) do
        refute Guard.safe_uri?(URI.parse("https://#{host}/"))
      end
    end
    refute called, "reserved local suffixes must be rejected before DNS resolution"
  end

  def test_rejects_invalid_dns_label_characters_before_resolution
    called = false
    Guard.stub(:resolve_addresses, ->(_name) { called = true; ["1.1.1.1"] }) do
      refute Guard.valid_resolver_host?("bad_name.example")
    end
    refute called
  end

  def test_http_for_pins_the_connection_to_the_checked_address
    http = Guard.http_for(URI.parse("https://example.com/x"), "93.184.216.34")

    assert_equal "93.184.216.34", http.ipaddr
    assert_equal "example.com", http.address
    assert_nil http.proxy_address, "an environment proxy must not bypass the pinned destination"
    assert http.use_ssl?
  end

  # Reserved, 6to4 relay and NAT64/6to4 forms that embed a private IPv4 address.
  def test_blocks_reserved_and_translated_forms
    %w[240.0.0.1 192.31.196.1 192.52.193.1 192.88.99.1 192.175.48.1 2620:4f:8000::1 64:ff9b::a00:1 64:ff9b:1::a00:1 2002:0a00:0001::1].each do |address|
      assert Guard.blocked_ip?(IPAddr.new(address)), "#{address} must be blocked"
    end
  end

  def test_web_fetch_uses_the_shared_pinned_request_boundary
    calls = []
    response = Struct.new(:code, :body).new("200", "<p>hello</p>")
    governor = Object.new
    def governor.permit?(*) = Master::Result.ok(true)
    fetch = Master::Io::WebFetch.new(governor:)
    handler = lambda do |uri, request, **options|
      calls << [uri, request, options]
      response
    end

    Guard.stub(:request, handler) do
      assert fetch.send(:fetch_one, "https://example.com/").ok?
    end

    uri, request, options = calls.fetch(0)
    assert_equal URI("https://example.com/"), uri
    assert_instance_of Net::HTTP::Get, request
    assert_equal "MASTER/1 (web_fetch)", request["User-Agent"]
    assert_equal fetch.class::MAX_FULL_BYTES, options.fetch(:max_bytes)
  end
  class FakeOutboundResponse
    attr_reader :code, :body, :chunks_read

    def initialize(code: "200", headers: {}, chunks: [])
      @code = code
      @headers = headers.transform_keys(&:downcase)
      @chunks = chunks
      @chunks_read = 0
    end

    def [](name)
      @headers[name.downcase]
    end

    def read_body
      @chunks.each do |chunk|
        @chunks_read += 1
        yield chunk
      end
    end

    def body=(value)
      @body = value
    end
  end

  class FakeOutboundHttp
    attr_reader :response, :timeout, :ipaddr
    attr_accessor :open_timeout, :read_timeout, :write_timeout

    def initialize(response)
      @response = response
      @started = false
    end

    def start
      @started = true
      yield self
    ensure
      @started = false
    end

    def request(_request)
      yield response
      response
    end

    def started?
      @started
    end

    def finish
      @started = false
    end
  end

  def test_shared_request_returns_a_bounded_body_from_the_pinned_connection
    uri = URI("https://example.com/data")
    request = Net::HTTP::Get.new(uri)
    response = FakeOutboundResponse.new(headers: { "Content-Length" => "5" }, chunks: ["he", "llo"])
    http = FakeOutboundHttp.new(response)
    pins = []

    Guard.stub(:pinned_address, ->(candidate) { pins << candidate; "93.184.216.34" }) do
      Guard.stub(:http_for, ->(candidate, address, timeout:) {
        assert_equal uri, candidate
        assert_equal "93.184.216.34", address
        assert_equal 3, timeout
        http
      }) do
        result = Guard.request(uri, request, max_bytes: 5, timeout: 3)
        assert_equal "hello", result.body
      end
    end

    assert_equal [uri], pins
    assert_equal 2, response.chunks_read
  end

  def test_shared_request_rejects_declared_oversize_before_reading_body
    uri = URI("https://example.com/data")
    response = FakeOutboundResponse.new(headers: { "Content-Length" => "101" }, chunks: ["small"])
    http = FakeOutboundHttp.new(response)

    Guard.stub(:pinned_address, "93.184.216.34") do
      Guard.stub(:http_for, ->(*_args, **_options) { http }) do
        error = assert_raises(Guard::ResponseTooLarge) do
          Guard.request(uri, Net::HTTP::Get.new(uri), max_bytes: 100)
        end
        assert_match(/exceeds 100 bytes/, error.message)
      end
    end

    assert_equal 0, response.chunks_read
  end

  def test_shared_request_stops_a_chunked_body_at_the_cap
    uri = URI("https://example.com/data")
    response = FakeOutboundResponse.new(chunks: ["123456", "78901", "ignored"])
    http = FakeOutboundHttp.new(response)

    Guard.stub(:pinned_address, "93.184.216.34") do
      Guard.stub(:http_for, http) do
        assert_raises(Guard::ResponseTooLarge) do
          Guard.request(uri, Net::HTTP::Get.new(uri), max_bytes: 10)
        end
      end
    end

    assert_equal 2, response.chunks_read
  end

  def test_shared_request_returns_redirects_without_following_them
    uri = URI("https://example.com/start")
    response = FakeOutboundResponse.new(code: "302", headers: { "Location" => "https://other.example/next" })
    http = FakeOutboundHttp.new(response)
    resolutions = []

    Guard.stub(:pinned_address, ->(candidate) { resolutions << candidate.to_s; "93.184.216.34" }) do
      Guard.stub(:http_for, http) do
        result = Guard.request(uri, Net::HTTP::Get.new(uri))
        assert_equal "302", result.code
        assert_equal "https://other.example/next", result["Location"]
      end
    end

    assert_equal ["https://example.com/start"], resolutions
  end

  def test_shared_request_does_not_connect_when_dns_policy_refuses
    uri = URI("https://example.com/data")
    Guard.stub(:pinned_address, nil) do
      Guard.stub(:http_for, ->(*_args, **_options) { flunk "HTTP must not be constructed without an approved pin" }) do
        assert_raises(SocketError) do
          Guard.request(uri, Net::HTTP::Get.new(uri))
        end
      end
    end
  end

end
