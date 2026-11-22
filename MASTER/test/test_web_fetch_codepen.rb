# frozen_string_literal: true

require_relative "test_helper"

class TestWebFetchCodePen < Minitest::Test
  Fetch = Master::Io::WebFetch

  def fetch = Fetch.new(governor: Object.new)

  def test_all_failed_components_are_an_error_not_empty_success
    tool = fetch
    failure = ->(*) { Master::Result.err("offline", category: :infrastructure) }

    tool.stub(:fetch_one, failure) do
      result = tool.send(:fetch_codepen, "artist", "pen-id")

      refute result.ok?
      assert_match(/all components/, result.message)
    end
  end

  def test_a_page_larger_than_the_text_limit_returns_its_first_text
    page = "<html><body>#{"<p>word </p>" * 4_000}</body></html>"
    response = Struct.new(:code, :body).new("200", page)
    result = fetch.send(:deliver, "https://example.test/", response)

    assert result.ok?
    assert_operator result.value!.bytesize, :<=, Fetch::MAX_BYTES + 200
    assert_includes result.value!, "word"
  end

  def test_partial_failure_is_disclosed_in_the_result
    tool = fetch
    response = lambda do |url, full: false|
      url.end_with?(".html") ? Master::Result.ok("<p>hello</p>") :
        Master::Result.err("component unavailable", category: :infrastructure)
    end

    tool.stub(:fetch_one, response) do
      result = tool.send(:fetch_codepen, "artist", "pen-id")

      assert result.ok?
      assert_includes result.value!, "<p>hello</p>"
      assert_includes result.value!, "Unavailable CodePen components: css, js"
    end
  end

  def test_http_get_uses_the_shared_pinned_and_bounded_request
    uri = URI("https://example.test/page")
    response = Struct.new(:code, :body).new("200", "body")
    calls = []
    handler = lambda do |candidate, request, **options|
      calls << [candidate, request, options]
      response
    end

    Master::Io::SsrfGuard.stub(:request, handler) do
      fetched = fetch.send(:http_get, uri)
      assert_equal "200", fetched.code
      assert_equal "body", fetched.body
    end

    candidate, request, options = calls.fetch(0)
    assert_equal uri, candidate
    assert_instance_of Net::HTTP::Get, request
    assert_equal "MASTER/1 (web_fetch)", request["User-Agent"]
    assert_equal Fetch::MAX_FULL_BYTES, options.fetch(:max_bytes)
    assert_equal Fetch::DEADLINE_S, options.fetch(:timeout)
    assert_equal Fetch::TIMEOUT, options.fetch(:open_timeout)
    assert_equal Fetch::TIMEOUT, options.fetch(:read_timeout)
    assert_equal Fetch::TIMEOUT, options.fetch(:write_timeout)
  end

  def test_http_get_translates_a_shared_response_cap_failure
    uri = URI("https://example.test/page")
    Master::Io::SsrfGuard.stub(:request, ->(*) { raise Master::Io::SsrfGuard::ResponseTooLarge }) do
      assert_raises(Fetch::TooLarge) { fetch.send(:http_get, uri) }
    end
  end
end
