# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/io/external_audit"

class ExternalAuditRedirectTest < Minitest::Test
  Guard = Master::Io::SsrfGuard

  def setup
    @audit = Master::Io::ExternalAudit.new(governor: nil)
  end

  def redirect(location)
    Net::HTTPFound.new("1.1", "302", "Found").tap { |response| response["Location"] = location }
  end

  def ok(body)
    Net::HTTPOK.new("1.1", "200", "OK").tap { |response| response.body = body }
  end

  def test_same_host_redirect_uses_a_fresh_bounded_request_for_each_hop
    responses = [redirect("/final"), ok("<p>done</p>")]
    calls = []
    handler = lambda do |uri, request, **options|
      calls << [uri.to_s, request, options]
      responses.shift
    end

    Guard.stub(:request, handler) do
      result = @audit.send(:fetch_page, URI("https://example.test/start"))
      assert_equal 200, result[0].code.to_i
      assert_equal URI("https://example.test/final"), result[1]
      assert_equal 1, result[2]
      assert_equal "<p>done</p>", result[3]
    end

    assert_equal ["https://example.test/start", "https://example.test/final"], calls.map(&:first)
    calls.each do |_url, request, options|
      assert_instance_of Net::HTTP::Get, request
      assert_equal "MASTER/1 (passive external assessment)", request["User-Agent"]
      assert_equal 1_048_576, options.fetch(:max_bytes)
      assert_equal 30, options.fetch(:timeout)
      assert_equal 10, options.fetch(:open_timeout)
      assert_equal 10, options.fetch(:read_timeout)
      assert_equal 10, options.fetch(:write_timeout)
    end
  end

  def test_redirect_reenters_the_guard_and_stops_if_the_next_dns_answer_is_unsafe
    calls = 0
    handler = lambda do |_uri, _request, **_options|
      calls += 1
      raise SocketError, "refused non-public destination" if calls == 2

      redirect("/next")
    end

    Guard.stub(:request, handler) do
      result = @audit.send(:fetch_page, URI("https://example.test/start"))
      refute result.ok?
      assert_match(/refused internal\/reserved destination/, result.message)
    end

    assert_equal 2, calls, "the second hop must be rechecked before its socket opens"
  end

  def test_cross_host_redirect_is_refused_without_requesting_the_new_host
    calls = []
    Guard.stub(:request, lambda { |uri, request, **options|
      calls << uri.to_s
      redirect("https://other.example/final")
    }) do
      result = @audit.send(:fetch_page, URI("https://example.test/start"))
      refute result.ok?
      assert_match(/redirect changes host/, result.message)
    end

    assert_equal ["https://example.test/start"], calls
  end

  def test_https_redirect_cannot_downgrade_to_http
    calls = []
    Guard.stub(:request, lambda { |uri, request, **options|
      calls << uri.to_s
      redirect("http://example.test/plain")
    }) do
      result = @audit.send(:fetch_page, URI("https://example.test/start"))
      refute result.ok?
      assert_match(/cannot downgrade/, result.message)
    end

    assert_equal ["https://example.test/start"], calls
  end

  def test_redirect_to_nonstandard_port_is_refused_before_the_next_request
    calls = []
    Guard.stub(:request, lambda { |uri, request, **options|
      calls << uri.to_s
      redirect("https://example.test:8443/private")
    }) do
      result = @audit.send(:fetch_page, URI("https://example.test/start"))
      refute result.ok?
      assert_match(/standard port/, result.message)
    end

    assert_equal ["https://example.test/start"], calls
  end
end
