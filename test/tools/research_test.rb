# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../master/tools/research"

class ResearchTest < Minitest::Test
  include TestHelper

  class Transport
    attr_reader :requests

    def initialize = (@requests = [])

    def request(method, url, timeout:, headers: {}, **_options)
      @requests << [method, url, headers]
      body = case url
             when /codepen\.io\/trending/
               '<a href="/alice/pen/bright-sky"><span>Bright Sky</span></a>'
             when /codepen\.io\/alice\/pen\/bright-sky\./
               "panel source"
             when /api\.github\.com\/search\/repositories/
               JSON.generate(items: [{ full_name: "example/agent", html_url: "https://github.com/example/agent",
                                       description: "A small agent", stargazers_count: 91,
                                       forks_count: 8, language: "Ruby", created_at: "2026-11-01T00:00:00Z",
                                       updated_at: "2026-11-06T00:00:00Z" }])
             when /export\.arxiv\.org\/api\/query/
               <<~XML
                 <?xml version="1.0" encoding="UTF-8"?>
                 <feed xmlns="http://www.w3.org/2005/Atom">
                   <entry>
                     <id>https://arxiv.org/abs/2601.12345v2</id>
                     <title>Useful Research</title>
                     <summary>A bounded abstract.</summary>
                     <published>2026-01-01T00:00:00Z</published>
                     <updated>2026-01-02T00:00:00Z</updated>
                     <author><name>Researcher One</name></author>
                   </entry>
                 </feed>
               XML
             when /ar5iv\.labs\.arxiv\.org/
               "<html><body><h1>Full paper</h1><p>Bounded full text.</p></body></html>"
             else
               raise "unexpected URL: #{url}"
             end
      Core::HTTP::Reply.new(status: 200, headers: {}, body:)
    end
  end

  def build
    sandbox do |root|
      transport = Transport.new
      verbs = { net: %w[codepen.io api.github.com export.arxiv.org ar5iv.labs.arxiv.org] }
      w = world(root, verbs, transport:)
      yield Master::Tools::Research.new(world: w), transport
    end
  end

  def test_tools_are_exposed_only_when_the_exact_hosts_are_permitted
    sandbox do |root|
      w = world(root, { net: ["api.github.com"] })
      research = Master::Tools::Research.new(world: w)

      expected = ["github.repositories"]
      expected.concat(Master::Tools::Research::BROWSER_TOOLS.map { |tool| tool.fetch("name") }) if Master::Tools::BrowserAgent.available?
      assert_equal expected, research.available_tools.map { |tool| tool.fetch("name") }
    end
  end

  def test_codepen_trending_and_inspection_are_read_only
    build do |research, transport|
      trending = JSON.parse(research.call(name: "codepen.trending", arguments: { "limit" => 4 }))
      assert_equal "Bright Sky", trending.dig("results", 0, "title")

      inspect = JSON.parse(research.call(name: "codepen.inspect",
                                          arguments: { "url" => "https://codepen.io/alice/pen/bright-sky" }))
      assert_equal %w[html css js], inspect.fetch("panels").keys
      assert transport.requests.all? { |method, _url, _headers| method == :get }
    end
  end

  def test_github_search_can_filter_to_new_repositories
    build do |research, transport|
      result = JSON.parse(research.call(name: "github.repositories",
                                        arguments: { "query" => "ruby agent", "created_after" => "2026-11-01",
                                                     "sort" => "stars", "limit" => 5 }))
      assert_equal "example/agent", result.dig("results", 0, "name")
      assert_match(/created%3A%3E%3D2026-11-01/, transport.requests.last[1])
    end
  end

  def test_arxiv_returns_ar5iv_links_and_bounded_full_text
    build do |research, _transport|
      result = JSON.parse(research.call(name: "arxiv.papers",
                                        arguments: { "query" => "robotics exoskeleton",
                                                     "full_text" => true, "limit" => 3 }))
      assert_equal "Useful Research", result.dig("results", 0, "title")
      assert_match(%r{https://ar5iv\.labs\.arxiv\.org/html/2601\.12345v2}, result.dig("results", 0, "ar5iv_url"))
      assert_match(/Bounded full text/, result.fetch("full_text"))
    end
  end

  def test_arxiv_abstract_search_does_not_require_ar5iv_permission
    sandbox do |root|
      transport = Transport.new
      w = world(root, { net: ["export.arxiv.org"] }, transport:)
      research = Master::Tools::Research.new(world: w)

      assert_includes research.available_tools.map { |tool| tool.fetch("name") }, "arxiv.papers"

      abstract = JSON.parse(research.call(name: "arxiv.papers",
                                          arguments: { "query" => "robotics exoskeleton", "limit" => 2 }))
      assert_equal "Useful Research", abstract.dig("results", 0, "title")

      full_text = JSON.parse(research.call(name: "arxiv.papers",
                                           arguments: { "query" => "robotics exoskeleton",
                                                        "full_text" => true, "limit" => 2 }))
      assert_match(/Full text unavailable/, full_text.fetch("full_text"))
      assert_equal 2, transport.requests.size
      assert transport.requests.all? { |_method, url, _headers| url.include?("export.arxiv.org") }
    end
  end

  def test_unknown_tools_are_not_dispatched
    build do |research, _transport|
      result = research.call(name: "arbitrary.shell", arguments: {})
      assert_match(/unknown research tool/, result)
    end
  end
end
