# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/io/external_audit"

class ExternalAuditRedirectTest < Minitest::Test
  Guard = Master::Io::SsrfGuard

  class FakeHttpResponse
    attr_reader :response

    def initialize(response)
      @response = response
    end

    def start
      yield self
    end

    def request(_request)
      yield response if block_given?
      response
    end
  end

  class RedirectResponse < Net::HTTPFound
    def initialize(location)
      super("1.1", "302", "Found")
      self["location"] = location
    end

    def read_body(*)
      yield "" if block_given?
      ""
    end
  end

  class OkResponse < Net::HTTPOK
    def initialize(body)
      super("1.1", "200", "OK")
      @payload = body
    end

    def read_body(*)
      yield @payload if block_given?
      @payload
    end
  end

  def setup
    @audit = Master::Io::ExternalAudit.new(governor: nil)
  end

  def test_same_host_redirect_resolves_and_pins_each_hop
    responses = [RedirectResponse.new("/final"), OkResponse.new("<p>done</p>")]
    addresses = ["93.184.216.34", "8.8.8.8"]
    resolutions = []
    connections = []

    Guard.stub(:pinned_address, lambda { |uri|
      resolutions << uri.to_s
      addresses.shift
    }) do
      Guard.stub(:http_for, lambda { |uri, address, timeout:|
        connections << [uri.to_s, address, timeout]
        FakeHttpResponse.new(responses.shift)
      }) do
        result = @audit.send(:fetch_page, URI("https://example.test/start"))
        assert_equal 200, result[0].code.to_i
        assert_equal URI("https://example.test/final"), result[1]
        assert_equal 1, result[2]
        assert_equal "<p>done</p>", result[3]
      end
    end

    assert_equal [
      "https://example.test/start",
      "https://example.test/final"
    ], resolutions
    assert_equal [
      ["https://example.test/start", "93.184.216.34", Master::Io::ExternalAudit::TIMEOUT],
      ["https://example.test/final", "8.8.8.8", Master::Io::ExternalAudit::TIMEOUT]
    ], connections
  end

  def test_redirect_rechecks_dns_and_stops_if_the_new_answer_is_unsafe
    responses = [RedirectResponse.new("/next")]
    addresses = ["93.184.216.34", nil]
    resolutions = []
    connection_count = 0

    Guard.stub(:pinned_address, lambda { |uri|
      resolutions << uri.to_s
      addresses.shift
    }) do
      Guard.stub(:http_for, lambda { |uri, address, timeout:|
        connection_count += 1
        FakeHttpResponse.new(responses.shift)
      }) do
        result = @audit.send(:fetch_page, URI("https://example.test/start"))
        refute result.ok?
        assert_match(/refused internal\/reserved destination/, result.message)
      end
    end

    assert_equal 2, resolutions.length
    assert_equal 1, connection_count, "the second hop must not connect after a failed address check"
  end

  def test_cross_host_redirect_is_refused_without_connecting_to_the_new_host
    resolutions = []
    connections = 0

    Guard.stub(:pinned_address, lambda { |uri|
      resolutions << uri.to_s
      "93.184.216.34"
    }) do
      Guard.stub(:http_for, lambda { |_uri, _address, timeout:|
        connections += 1
        FakeHttpResponse.new(RedirectResponse.new("https://other.example/final"))
      }) do
        result = @audit.send(:fetch_page, URI("https://example.test/start"))
        refute result.ok?
        assert_match(/redirect changes host/, result.message)
      end
    end

    assert_equal ["https://example.test/start"], resolutions
    assert_equal 1, connections
  end

  def test_https_redirect_cannot_downgrade_to_http
    resolutions = []
    connections = 0

    Guard.stub(:pinned_address, lambda { |uri|
      resolutions << uri.to_s
      "93.184.216.34"
    }) do
      Guard.stub(:http_for, lambda { |_uri, _address, timeout:|
        connections += 1
        FakeHttpResponse.new(RedirectResponse.new("http://example.test/plain"))
      }) do
        result = @audit.send(:fetch_page, URI("https://example.test/start"))
        refute result.ok?
        assert_match(/cannot downgrade/, result.message)
      end
    end

    assert_equal ["https://example.test/start"], resolutions
    assert_equal 1, connections
  end
end
