# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/io/gist"
require_relative "../lib/io/code_pen"

class PublicFetcherTransportTest < Minitest::Test
  Guard = Master::Io::SsrfGuard

  Governor = Class.new do
    def permit?(*)
      Master::Result.ok("permitted")
    end
  end

  def response(body)
    Net::HTTPOK.new("1.1", "200", "OK").tap { |item| item.body = body }
  end

  def test_gist_uses_the_shared_request_with_a_bounded_json_response
    gist = Master::Io::Gist.new(governor: Governor.new)
    calls = []
    handler = lambda do |uri, request, **options|
      calls << [uri, request, options]
      response("{\"files\":{}}")
    end

    Guard.stub(:request, handler) do
      result = gist.send(:get, "https://api.github.com/gists/0123456789abcdef")
      assert_equal "200", result.code
    end

    uri, request, options = calls.fetch(0)
    assert_equal "api.github.com", uri.host
    assert_equal "/gists/0123456789abcdef", request.path
    assert_equal "MASTER/1 (gist)", request["User-Agent"]
    assert_equal "application/vnd.github+json", request["Accept"]
    assert_equal 2 * Master::Io::Gist::MAX_BYTES, options.fetch(:max_bytes)
    assert_equal Master::Io::Gist::TIMEOUT, options.fetch(:timeout)
  end

  def test_codepen_uses_the_shared_request_and_fails_closed_on_oversize
    pen = Master::Io::CodePen.new(governor: Governor.new)
    calls = []
    handler = lambda do |uri, request, **options|
      calls << [uri, request, options]
      raise Guard::ResponseTooLarge, "response body exceeds cap"
    end

    Guard.stub(:request, handler) do
      assert_raises(Guard::ResponseTooLarge) { pen.send(:get, "https://codepen.io/trending") }
    end

    uri, request, options = calls.fetch(0)
    assert_equal "codepen.io", uri.host
    assert_equal "/trending", request.path
    assert_equal "MASTER/1 (codepen)", request["User-Agent"]
    assert_equal Master::Io::CodePen::MAX_BYTES, options.fetch(:max_bytes)
    assert_equal Master::Io::CodePen::TIMEOUT, options.fetch(:timeout)
  end
end
