# frozen_string_literal: true

require "minitest/autorun"
require_relative "../__shared/app/services/shared/outbound_http"
require_relative "../brgen/app/lib/fediverse/client"

module Shared
  module Llm
    DEFAULT_MODEL = "test-model" unless const_defined?(:DEFAULT_MODEL)
  end
end
require_relative "../__shared/app/services/shared/scrape"

class FediverseSsrfTest < Minitest::Test
  def test_loopback_https_is_refused
    refute Fediverse::Client.public_https?(URI("https://127.0.0.1/actor"))
  end

  def test_link_local_metadata_is_refused
    refute Fediverse::Client.public_https?(URI("https://169.254.169.254/latest/meta-data"))
  end

  def test_non_443_is_refused
    refute Fediverse::Client.public_https?(URI("https://example.com:8443/actor"))
  end

  def test_plain_http_is_refused_by_the_predicate
    refute Shared::OutboundHttp.public_https?(URI("http://example.com/actor"))
  end

  def test_https_on_port_80_is_refused_by_the_predicate
    refute Shared::OutboundHttp.public_https?(URI("https://example.com:80/actor"))
  end

  # The predicate tests above pass whether or not the request path consults it,
  # so they cannot tell a guard from a decoration. These drive the real method.
  def test_request_refuses_a_loopback_host
    error = assert_raises(SocketError) { Shared::OutboundHttp.request(URI("https://127.0.0.1/actor")) }
    assert_match(/unsafe or unresolvable/, error.message)
  end

  def test_ipv4_mapped_loopback_is_refused
    assert Shared::OutboundHttp.unsafe_ip?("::ffff:127.0.0.1")
    assert Shared::OutboundHttp.unsafe_ip?("::ffff:10.0.0.1")
    assert Shared::OutboundHttp.unsafe_ip?("::ffff:169.254.169.254")
  end

  def test_ipv6_targets_must_be_global_unicast_and_not_documentation_space
    %w[4000::1 5f00::1 2d00::1 2e00::1 3000::1 3800::1 3c00::1 3e00::1 3f00::1 3ffe::1 3fff::1 2001:db8::1 2620:4f:8000::1 ::a00:1 fc00::1 fd00::1 fe80::1 ff02::1].each do |address|
      assert Shared::OutboundHttp.unsafe_ip?(address), "#{address} must not be an outbound target"
    end
    refute Shared::OutboundHttp.unsafe_ip?("2606:4700:4700::1111")
  end

  def test_special_ipv4_ranges_are_refused
    %w[0.1.2.3 100.64.0.1 169.254.1.1 192.31.196.1 192.52.193.1 192.168.1.1 192.175.48.1 198.18.0.1 203.0.113.1 224.0.0.1 240.0.0.1 255.255.255.255].each do |address|
      assert Shared::OutboundHttp.unsafe_ip?(address), "#{address} must not be an outbound target"
    end
    refute Shared::OutboundHttp.unsafe_ip?("93.184.216.34")
  end

  def test_dns_name_limits_reject_overlong_labels_and_wire_names
    assert Shared::OutboundHttp.valid_resolver_host?("example.com")
    assert Shared::OutboundHttp.valid_resolver_host?("127.0.0.1")
    refute Shared::OutboundHttp.valid_resolver_host?("#{"a" * 64}.example")
    refute Shared::OutboundHttp.valid_resolver_host?(Array.new(4, "a" * 63).join("."))
  end

  def test_single_label_resolver_names_are_refused_before_dns
    called = false
    resolver = Shared::OutboundHttp.singleton_class
    resolver.alias_method(:saved_single_label_resolver, :resolve_addresses)
    Shared::OutboundHttp.define_singleton_method(:resolve_addresses) do |_host|
      called = true
      ["93.184.216.34"]
    end
    assert_nil Shared::OutboundHttp.public_address("instance-data")
    refute called, "single-label names must not use resolver search domains"
  ensure
    resolver.alias_method(:resolve_addresses, :saved_single_label_resolver)
    resolver.remove_method(:saved_single_label_resolver)
  end

  def test_pinned_connection_ignores_environment_proxy
    old_proxy = ENV["https_proxy"]
    ENV["https_proxy"] = "http://127.0.0.1:9"
    http = Shared::OutboundHttp.pinned_connection(URI("https://rebind.test/actor"), "93.184.216.34")

    assert_equal "93.184.216.34", http.ipaddr
    assert_nil http.proxy_address, "an environment proxy must not bypass the pinned destination"
  ensure
    old_proxy.nil? ? ENV.delete("https_proxy") : ENV["https_proxy"] = old_proxy
  end

  def test_pinned_connection_respects_bounded_client_timeouts
    http = Shared::OutboundHttp.pinned_connection(
      URI("https://rebind.test/actor"),
      "93.184.216.34",
      open_timeout: 15,
      read_timeout: 300
    )

    assert_equal 15, http.open_timeout
    assert_equal 300, http.read_timeout
    assert_equal Shared::OutboundHttp::TIMEOUT, http.write_timeout
  end

  def test_request_refuses_a_non_443_port
    assert_raises(URI::InvalidURIError) { Shared::OutboundHttp.request(URI("https://example.com:8443/actor")) }
  end

  def test_request_refuses_reserved_ipv6_before_connecting
    %w[4000::1 3fff::1].each do |address|
      error = with_stubbed_dns(address) do
        assert_raises(SocketError) do
          Shared::OutboundHttp.request(URI("https://reserved-ipv6.test/actor"))
        end
      end
      assert_match(/unsafe or unresolvable/, error.message)
    end
  end

  def test_client_returns_nil_rather_than_raising_at_a_loopback_host
    assert_nil Fediverse::Client.request(:get, "https://127.0.0.1/actor")
  end

  # The point of the whole exercise: the address that was checked is the address
  # the socket connects to. Without ipaddr= the host would be resolved a second
  # time inside Net::HTTP and a rebinding answer would land on the private net.
  def test_the_checked_address_is_the_one_connected_to
    pinned = with_stubbed_dns("93.184.216.34") do
      with_stubbed_request(->(http, _request, _block) { http.ipaddr }) do
        Shared::OutboundHttp.request(URI("https://rebind.test/actor"))
      end
    end

    assert_equal "93.184.216.34", pinned
  end

  def test_a_mixed_public_and_private_answer_set_is_refused_without_connecting
    connected = false
    with_stubbed_dns("93.184.216.34", "127.0.0.1") do
      with_stubbed_request(->(*) { connected = true; flunk "mixed DNS answers must never connect" }) do
        error = assert_raises(SocketError) do
          Shared::OutboundHttp.request(URI("https://rebind.test/actor"))
        end
        assert_match(/unsafe or unresolvable/, error.message)
      end
    end
    refute connected
  end

  def test_all_public_dns_answers_are_accepted_and_the_first_is_pinned
    pinned = with_stubbed_dns("93.184.216.34", "8.8.8.8") do
      with_stubbed_request(->(http, _request, _block) { http.ipaddr }) do
        Shared::OutboundHttp.request(URI("https://rebind.test/actor"))
      end
    end

    assert_equal "93.184.216.34", pinned
  end

  def test_request_refuses_credentials_and_fragments
    [
      URI("https://user:pass@rebind.test/actor"),
      URI("https://rebind.test/actor#fragment")
    ].each do |uri|
      assert_raises(URI::InvalidURIError) { Shared::OutboundHttp.request(uri) }
    end
  end

  def test_reserved_transition_ipv6_and_non_global_ranges_are_refused
    %w[64:ff9b::a00:1 64:ff9b:1::a00:1 2002:0a00:0001::1 2001:0::1 4000::1].each do |address|
      assert Shared::OutboundHttp.unsafe_ip?(address), "#{address} must not be an outbound target"
    end
  end

  def test_dns_label_characters_are_bounded_before_resolution
    assert Shared::OutboundHttp.valid_resolver_host?("example.com")
    refute Shared::OutboundHttp.valid_resolver_host?("bad_name.example")
    refute Shared::OutboundHttp.valid_resolver_host?("-bad.example")
    refute Shared::OutboundHttp.valid_resolver_host?("bad-.example")
  end

  # The cap is enforced while reading, so a hostile server cannot make this
  # process hold its whole answer before anything checks the size.
  def test_a_body_past_the_cap_stops_the_read
    response = ChunkedResponse.new(%w[aaaa bbbb cccc])

    with_stubbed_exchange(response) do
      assert_raises(Shared::OutboundHttp::BodyTooLarge) do
        Shared::OutboundHttp.request(URI("https://rebind.test/actor"), max_body: 6)
      end
    end
    assert_equal 2, response.chunks_read
  end

  def test_a_body_inside_the_cap_is_kept_whole
    response = ChunkedResponse.new(%w[aaaa bbbb])

    with_stubbed_exchange(response) do
      Shared::OutboundHttp.request(URI("https://rebind.test/actor"), max_body: 8)
    end
    assert_equal "aaaabbbb", response.body
  end

  def test_total_deadline_interrupts_a_slow_response
    with_stubbed_dns("93.184.216.34") do
      with_stubbed_request(lambda do |_http, _request, _block|
        sleep 0.05
        Net::HTTPOK.new("1.1", "200", "OK")
      end) do
        error = assert_raises(Shared::OutboundHttp::DeadlineExceeded) do
          Shared::OutboundHttp.request(
            URI("https://rebind.test/actor"),
            open_timeout: 1, read_timeout: 1, write_timeout: 1,
            total_timeout: 0.01
          )
        end
        assert_match(/total deadline/, error.message)
      end
    end
  end

  def test_total_deadline_defaults_to_the_largest_socket_timeout_and_is_bounded
    assert_raises(ArgumentError) do
      Shared::OutboundHttp.request(
        URI("https://rebind.test/actor"), total_timeout: Shared::OutboundHttp::MAX_TOTAL_TIMEOUT + 1
      )
    end
  end

  def test_redirects_are_returned_but_never_followed_by_the_transport
    response = Net::HTTPFound.new("1.1", "302", "Found")
    response["location"] = "https://127.0.0.1/private"
    calls = 0

    with_stubbed_dns("93.184.216.34") do
      with_stubbed_request(lambda do |_http, _request, _block|
        calls += 1
        response
      end) do
        result = Shared::OutboundHttp.request(URI("https://rebind.test/actor"))
        assert_instance_of Net::HTTPFound, result
      end
    end

    assert_equal 1, calls, "redirects must not create a second outbound connection"
  end

  def test_media_body_budget_is_bounded_and_larger_than_json
    assert_operator Shared::OutboundHttp::MAX_MEDIA_BODY, :>, Shared::OutboundHttp::MAX_BODY
    assert_operator Shared::OutboundHttp::MAX_MEDIA_BODY, :<=, 8_000_000
  end

  def test_an_oversized_body_is_a_network_error_callers_already_rescue
    assert_includes Shared::OutboundHttp::NETWORK_ERRORS, Shared::OutboundHttp::BodyTooLarge
  end
\n  def test_total_deadline_is_a_network_error_callers_already_rescue\n    assert_includes Shared::OutboundHttp::NETWORK_ERRORS, Shared::OutboundHttp::DeadlineExceeded\n  end\n
  private

  ChunkedResponse = Struct.new(:chunks, :body, :chunks_read) do
    def read_body
      self.chunks_read = 0
      chunks.each do |chunk|
        self.chunks_read += 1
        yield chunk
      end
    end
  end

  # Hands the request block a response that streams its chunks, instead of
  # opening a socket.
  def with_stubbed_exchange(response)
    with_stubbed_dns("93.184.216.34") do
      with_stubbed_request(->(_http, _request, block) { block.call(response) }) { yield }
    end
  end

  def with_stubbed_request(handler)
    Net::HTTP.alias_method(:saved_outbound_test_request, :request)
    Net::HTTP.define_method(:request) do |request, &block|
      handler.call(self, request, block)
    end
    yield
  ensure
    Net::HTTP.alias_method(:request, :saved_outbound_test_request)
    Net::HTTP.remove_method(:saved_outbound_test_request)
  end

  # Answers the lookup with fixed addresses and reports the ipaddr Net::HTTP was
  # left holding, instead of opening a socket.
  def with_stubbed_dns(*addresses)
    resolver = Shared::OutboundHttp.singleton_class
    resolver.alias_method(:saved_outbound_test_resolver, :resolve_addresses)
    Shared::OutboundHttp.define_singleton_method(:resolve_addresses) { |_host| addresses }
    yield
  ensure
    resolver.alias_method(:resolve_addresses, :saved_outbound_test_resolver)
    resolver.remove_method(:saved_outbound_test_resolver)
  end
end

# Every outbound HTTP call in app code carries a timeout.
#
# Net::HTTP's defaults are sixty seconds to open and sixty to read, and the
# convenience calls — Net::HTTP.get, get_response, post, post_form — accept no
# timeout at all. On a one-vCPU box a feed read that hangs inside a render holds
# a Falcon fiber and the page for two minutes. A call that opens a connection
# (start, new, URI.open) must name read_timeout in the same file; a convenience
# call is refused outright, because it cannot be given one.
class ScrapeDnsPinningTest < Minitest::Test
  def test_scrape_refuses_mixed_public_and_private_dns_answers
    resolver = ->(_host) { ["93.184.216.34", "127.0.0.1"] }
    refute Shared::Scrape.public_http_url?("https://rebind.test/", resolver:)
  end

  def test_scrape_accepts_all_public_answers
    resolver = ->(_host) { ["93.184.216.34", "8.8.8.8"] }
    assert Shared::Scrape.public_http_url?("https://public.test/", resolver:)
  end

  def test_scrape_rejects_transition_and_non_global_ipv6
    %w[64:ff9b::a00:1 64:ff9b:1::a00:1 2002:0a00:0001::1 2001:0::1 4000::1].each do |address|
      resolver = ->(_host) { [address] }
      refute Shared::Scrape.public_http_url?("https://rebind.test/", resolver:), "#{address} must be blocked"
    end
  end

  def test_scrape_rejects_url_credentials_fragments_and_local_suffixes
    resolver = ->(_host) { flunk "invalid URL must be rejected before resolving" }
    refute Shared::Scrape.public_http_url?("https://user:pass@example.com/", resolver:)
    refute Shared::Scrape.public_http_url?("https://example.com/#fragment", resolver:)
    refute Shared::Scrape.public_http_url?("http://printer.local/", resolver:)
  end

  def test_scrape_rejects_nonstandard_http_ports_before_dns
    resolver = ->(_host) { flunk "non-standard ports must be refused before DNS" }
    refute Shared::Scrape.public_http_url?("https://example.com:8443/", resolver:)
    refute Shared::Scrape.public_http_url?("http://example.com:8080/", resolver:)
    refute Shared::Scrape.public_browser_url?(URI("https://example.com:8443/"))
    refute Shared::Scrape.public_browser_url?(URI("http://example.com:8080/"))
  end

  def test_chromium_resolver_rules_pin_hosts_and_block_unlisted_names
    rules = Shared::Scrape.host_resolver_rules(
      "example.com" => "93.184.216.34",
      "cdn.example" => "2606:4700:4700::1111"
    )

    assert_includes rules, "MAP cdn.example [2606:4700:4700::1111]"
    assert_includes rules, "MAP example.com 93.184.216.34"
    assert rules.end_with?("MAP * ^NOTFOUND")
  end

  def test_chromium_resolver_rules_refuse_a_non_public_pin
    assert_raises(ArgumentError) do
      Shared::Scrape.host_resolver_rules("example.com" => "169.254.169.254")
    end
  end
end

class OutboundHttpTimeoutTest < Minitest::Test
  RAILS = File.expand_path("..", __dir__)
  SOURCE_DIRECTORIES = %w[app lib engines].freeze

  UNBOUNDABLE = /Net::HTTP\.(get|get_response|post|post_form)\s*\(/
  OPENS = /Net::HTTP\.(start|new)\s*\(|URI\.open\s*\(/

  def self.findings(source, label)
    code = source.lines.reject { |line| line.lstrip.start_with?("#") }.join
    found = code.scan(UNBOUNDABLE).map { |(call)| "#{label}: Net::HTTP.#{call} cannot take a timeout — use Net::HTTP.start with open_timeout/read_timeout" }
    found << "#{label}: opens a connection and never names read_timeout" if code.match?(OPENS) && !code.include?("read_timeout")
    found
  end

  def self.source_files
    Dir.children(RAILS).flat_map do |entry|
      root = File.join(RAILS, entry)
      next [] unless File.directory?(root)

      SOURCE_DIRECTORIES.flat_map { |child| Dir.glob(File.join(root, child, "**", "*.rb")) }
    end.uniq.reject { |path| path.include?("/test/") }
  end

  def test_no_app_file_makes_an_unbounded_call
    files = self.class.source_files
    assert_operator files.size, :>, 0, "the outbound HTTP inventory matched no Ruby files"
    required = %w[
      __shared/app/services/shared/outbound_http.rb
      bsdports/app/services/ports/openbsd/package_index_fetcher.rb
      bsdports/app/services/ports/openbsd/ports_tarball.rb
    ].map { |path| File.join(RAILS, path) }
    assert_empty required - files, "the outbound HTTP inventory missed a core network client"

    found = files.flat_map { |path| self.class.findings(File.read(path).scrub, path.delete_prefix("#{RAILS}/")) }
    assert_empty found, found.join("\n")
  end

  def test_a_convenience_call_is_named
    found = self.class.findings("res = Net::HTTP.get_response(uri)\n", "planted.rb")
    assert_equal 1, found.size
    assert_match(/Net::HTTP.get_response cannot take a timeout/, found.first)
  end

  def test_a_connection_without_read_timeout_is_named
    found = self.class.findings("Net::HTTP.start(host, 443, use_ssl: true) { |h| h.get(path) }\n", "planted.rb")
    assert_match(/never names read_timeout/, found.first.to_s)
  end

  def test_a_bounded_connection_and_a_comment_pass
    source = "# Net::HTTP.get takes no timeout, so this does not use it\n"              "Net::HTTP.start(host, 443, open_timeout: 5, read_timeout: 10) { |h| h.get(path) }\n"
    assert_empty self.class.findings(source, "planted.rb")
  end
end
