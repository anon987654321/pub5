# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/io/youtube_transcript"
require_relative "../lib/io/web_search"
require_relative "../lib/io/github_repo_miner"
require_relative "../lib/io/arxiv_research"
require_relative "../lib/io/subdomain_orchestrator"

class BoundedPublicFetcherTransportTest < Minitest::Test
  Guard = Master::Io::SsrfGuard

  def response(body = "{}", code: "200")
    Struct.new(:code, :body).new(code, body)
  end

  def capture_request(result = response)
    calls = []
    handler = lambda do |uri, request, **options|
      calls << [uri, request, options]
      result
    end
    Guard.stub(:request, handler) { yield calls }
  end

  def test_youtube_watch_fetch_uses_bounded_get
    tool = Master::Io::YoutubeTranscript.new(governor: Object.new)
    capture_request(response("<html></html>")) do |calls|
      tool.send(:get_response, "https://www.youtube.com/watch?v=abcdefghijk")
      uri, request, options = calls.fetch(0)
      assert_equal "www.youtube.com", uri.host
      assert_instance_of Net::HTTP::Get, request
      assert_equal "MASTER/1 (youtube_transcript)", request["User-Agent"]
      assert_equal 2 * 1024 * 1024, options.fetch(:max_bytes)
      assert_equal 15, options.fetch(:timeout)
    end
  end

  def test_youtube_player_request_uses_bounded_post
    tool = Master::Io::YoutubeTranscript.new(governor: Object.new)
    uri = URI("https://www.youtube.com/youtubei/v1/player?key=public-test")
    payload = { videoId: "abcdefghijk", context: { client: { clientName: "WEB" } } }

    capture_request(response("{}")) do |calls|
      tool.send(:http_json, uri, payload)
      candidate, request, options = calls.fetch(0)
      assert_equal uri, candidate
      assert_instance_of Net::HTTP::Post, request
      assert_equal "application/json", request["Content-Type"]
      assert_equal payload, JSON.parse(request.body, symbolize_names: true)
      assert_equal 2 * 1024 * 1024, options.fetch(:max_bytes)
    end
  end

  def test_web_search_uses_shared_response_cap
    tool = Master::Io::WebSearch.new(governor: Object.new)
    capture_request(response("<html>results</html>")) do |calls|
      tool.fetch_search_response("Ruby SSRF")
      uri, request, options = calls.fetch(0)
      assert_equal "html.duckduckgo.com", uri.host
      assert_instance_of Net::HTTP::Get, request
      assert_equal "MASTER/1 (web_search)", request["User-Agent"]
      assert_equal 2 * 1024 * 1024, options.fetch(:max_bytes)
      assert_equal 10, options.fetch(:timeout)
    end
  end

  def test_github_repository_search_uses_shared_response_cap
    tool = Master::Io::GitHubRepoMiner.new(governor: Object.new)
    capture_request(response("{\"items\":[] }")) do |calls|
      tool.send(:fetch_response, query: "ruby security", sort: "stars", limit: 5)
      uri, request, options = calls.fetch(0)
      assert_equal "api.github.com", uri.host
      assert_instance_of Net::HTTP::Get, request
      assert_equal "application/vnd.github+json", request["Accept"]
      assert_equal "2022-11-28", request["X-GitHub-Api-Version"]
      assert_equal 2 * 1024 * 1024, options.fetch(:max_bytes)
    end
  end

  def test_arxiv_metadata_and_html_use_same_bounded_transport
    tool = Master::Io::ArxivResearch.new(governor: Object.new)
    [
      URI("https://export.arxiv.org/api/query?search_query=all:ruby"),
      URI("https://ar5iv.labs.arxiv.org/html/2601.12345")
    ].each do |uri|
      capture_request(response("<feed/>")) do |calls|
        tool.send(:get_response, uri)
        candidate, request, options = calls.fetch(0)
        assert_equal uri, candidate
        assert_instance_of Net::HTTP::Get, request
        assert_equal 2 * 1024 * 1024, options.fetch(:max_bytes)
        assert_equal 15, options.fetch(:timeout)
      end
    end
  end

  def test_subdomain_probe_caps_status_response
    tool = Master::Io::SubdomainOrchestrator.new
    capture_request(response("healthy")) do |calls|
      result = tool.send(:probe_http, "https://example.com/up", timeout: 4)
      assert_equal({ ok: true, status: 200, body: "healthy" }, result)
      uri, request, options = calls.fetch(0)
      assert_equal "example.com", uri.host
      assert_instance_of Net::HTTP::Get, request
      assert_equal "MASTER/1 (subdomain_orchestrator)", request["User-Agent"]
      assert_equal 4_096, options.fetch(:max_bytes)
      assert_equal 4, options.fetch(:timeout)
    end
  end
end
