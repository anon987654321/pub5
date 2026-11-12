# frozen_string_literal: true

# Boot-free by design (the lib/gap.rb precedent): this file loads without the
# bundle or test_helper, so the policy, crawler, filter and scout contracts run
# on any Ruby with minitest. Ferrum is never required; browsers are faked.
require "minitest/autorun"
require "tmpdir"
require "json"
require_relative "../lib/portal_agent"

module PortalFakes
  class Node
    attr_reader :attrs, :text, :children, :clicks
    def initialize(attrs: {}, text: "", children: {}, on_click: nil)
      @attrs = attrs; @text = text; @children = children
      @on_click = on_click; @clicks = 0
    end
    def [](name); @attrs[name]; end
    def at_css(sel); @children[sel]; end
    def click; @clicks += 1; @on_click.call if @on_click; end
  end

  class Network
    attr_reader :waits
    def initialize; @waits = 0; end
    def wait_for_idle(timeout: 15); @waits += 1; end
  end

  class Browser
    SEL = { "row" => "tr.paper", "title" => "h3.title",
            "link" => "a.paper-link", "next" => "a.next" }.freeze
    attr_accessor :url, :html, :pages, :mark_node
    attr_reader :network, :page_index, :backs
    def initialize(pages: [], url: "https://portal.example.edu/list")
      @pages = pages; @page_index = 0; @url = url
      @html = '<html><input type="password" value="hunter2"><input type="text" value="keep"></html>'
      @network = Network.new; @backs = 0
      @mark_node = Node.new(attrs: { "href" => "/something" })
    end
    def current_url; @url; end
    def body; @html; end
    def evaluate(_js); [{ "id" => 0, "tag" => "A", "text" => "Something" }]; end
    def screenshot(**_opts); "aW1n"; end
    def advance; @page_index += 1; end
    def back; @backs += 1; end
    def current; @pages[@page_index] || { rows: [], next: nil }; end
    def css(sel); sel == SEL["row"] ? current[:rows] : []; end
    def at_css(sel)
      return current[:next] if sel == SEL["next"]
      if sel =~ /data-agent-id="(\d+)"/
        return Regexp.last_match(1) == "0" ? @mark_node : nil
      end
      nil
    end
    def self.row(title, href)
      Node.new(children: { SEL["title"] => Node.new(text: title),
                           SEL["link"] => Node.new(attrs: { "href" => href }) })
    end
    def self.next_node(browser, disabled: false, stuck: false)
      attrs = disabled ? { "disabled" => "" } : {}
      Node.new(attrs: attrs, on_click: stuck ? nil : -> { browser.advance })
    end
    def self.with_pages(specs)
      b = new
      b.pages = specs.map do |s|
        nxt = case s[:next]
              when :none then nil
              when :disabled then next_node(b, disabled: true)
              when :stuck then next_node(b, stuck: true)
              else next_node(b)
              end
        { rows: s[:rows], next: nxt }
      end
      b
    end
  end

  class Gateway
    def initialize(actions); @actions = actions.dup; end
    def action(_snap, _history); @actions.shift || { "do" => "wait" }; end
  end
end

class TestPortalAgentPolicy < Minitest::Test
  P = Master::PortalAgent
  def setup
    @policy = P::Policy.new(allow_host: "portal.example.edu")
    @url = "https://portal.example.edu/list"
  end
  def test_whitelist_rejects_unknown_action
    assert_raises(P::PolicyError) { @policy.validate!({ "do" => "type", "text" => "x" }, @url) }
  end
  def test_click_requires_integer_id
    assert_raises(P::PolicyError) { @policy.validate!({ "do" => "click", "id" => "3" }, @url) }
  end
  def test_valid_click_passes
    assert_equal "click", @policy.validate!({ "do" => "click", "id" => 3 }, @url)
  end
  def test_off_domain_rejected
    assert_raises(P::PolicyError) { @policy.validate!({ "do" => "wait" }, "https://evil.example/") }
  end
  def test_redact_strips_password_value_only
    out = P::Policy.redact('<input type="password" value="hunter2"><input type="text" value="keep">')
    refute_includes out, "hunter2"
    assert_includes out, "[REDACTED]"
    assert_includes out, "keep"
  end
end

class TestPortalAgentCrawler < Minitest::Test
  P = Master::PortalAgent
  F = PortalFakes
  def setup; @dir = Dir.mktmpdir("portal-agent-test"); end
  def teardown; FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir); end
  def crawl(browser, **opts)
    P::Crawler.new(browser, selectors: F::Browser::SEL, evidence_dir: @dir, delay: 0, **opts).call
  end
  def test_dedupes_and_stops_on_disabled_next
    b = F::Browser.with_pages([
      { rows: [F::Browser.row("A", "/a"), F::Browser.row("B", "/b")], next: :enabled },
      { rows: [F::Browser.row("B", "/b"), F::Browser.row("C", "/c")], next: :disabled }
    ])
    c = crawl(b)
    assert_equal "DONE", c.status
    assert_equal %w[/a /b /c], c.papers.map { |p| p["link"] }
  end
  def test_stops_when_next_absent
    b = F::Browser.with_pages([{ rows: [F::Browser.row("A", "/a")], next: :none }])
    assert_equal "DONE", crawl(b).status
  end
  def test_zero_rows_is_inconclusive
    b = F::Browser.with_pages([{ rows: [], next: :none }])
    c = crawl(b)
    assert_equal "INCONCLUSIVE", c.status
    assert_match(/zero rows/, c.reason)
  end
  def test_no_advance_is_inconclusive
    b = F::Browser.with_pages([
      { rows: [F::Browser.row("A", "/a")], next: :stuck },
      { rows: [F::Browser.row("A", "/a")], next: :none }
    ])
    c = crawl(b)
    assert_equal "INCONCLUSIVE", c.status
    assert_match(/did not advance/, c.reason)
  end
  def test_page_budget_is_inconclusive
    b = F::Browser.with_pages([
      { rows: [F::Browser.row("A", "/a")], next: :enabled },
      { rows: [F::Browser.row("B", "/b")], next: :enabled }
    ])
    c = crawl(b, max_pages: 1)
    assert_equal "INCONCLUSIVE", c.status
    assert_match(/budget/, c.reason)
  end
  def test_evidence_written_and_redacted
    b = F::Browser.with_pages([
      { rows: [F::Browser.row("A", "/a")], next: :enabled },
      { rows: [F::Browser.row("B", "/b")], next: :disabled }
    ])
    crawl(b)
    manifest = JSON.parse(File.read(File.join(@dir, "manifest.json")))
    assert_equal "DONE", manifest["status"]
    assert_equal 2, manifest["pages_visited"]
    assert File.file?(File.join(@dir, "papers.json"))
    assert File.file?(File.join(@dir, "page_0.jpg"))
    html = File.read(File.join(@dir, "page_0.html"))
    refute_includes html, "hunter2"
    assert_includes html, "[REDACTED]"
  end
end

class TestPortalAgentFilter < Minitest::Test
  F = Master::PortalAgent::Filter
  def test_presort_buckets
    papers = [
      { "title" => "Battery electric bus charging infrastructure" },
      { "title" => "Hydrogen fuel-cell trucks" },
      { "title" => "E-bike electrification in Oslo" },
      { "title" => "Comparing hybrid and electric vehicles" },
      { "title" => "Medieval poetry" }
    ]
    out = F.presort(papers)
    assert_equal 1, out["ev"].size
    assert_equal 2, out["maybe"].size
    assert_equal 2, out["other"].size
  end
end

class TestPortalAgentSnapshot < Minitest::Test
  def test_capture_returns_url_marks_image
    snap = Master::PortalAgent::Snapshot.capture(PortalFakes::Browser.new)
    assert_equal "https://portal.example.edu/list", snap["url"]
    assert_equal 1, snap["marks"].size
    assert_equal "aW1n", snap["image_base64"]
  end
end

class TestPortalAgentGateway < Minitest::Test
  def test_requires_env_lane
    u = ENV.delete("MASTER_LLM_GATEWAY_URL"); k = ENV.delete("MASTER_LLM_GATEWAY_KEY")
    assert_raises(ArgumentError) { Master::PortalAgent::Gateway.new }
  ensure
    ENV["MASTER_LLM_GATEWAY_URL"] = u if u
    ENV["MASTER_LLM_GATEWAY_KEY"] = k if k
  end
end

class TestPortalAgentScout < Minitest::Test
  P = Master::PortalAgent
  F = PortalFakes
  def setup
    @policy = P::Policy.new(allow_host: "portal.example.edu")
    @browser = F::Browser.new
  end
  def scout(actions, handoff: nil)
    P::Scout.new(@browser, policy: @policy, gateway: F::Gateway.new(actions), handoff: handoff)
  end
  def test_done_returns_selectors
    sel = scout([{ "do" => "done", "selectors" => F::Browser::SEL }]).call
    assert_equal F::Browser::SEL, sel
  end
  def test_stale_id_is_inconclusive
    assert_raises(P::Inconclusive) { scout([{ "do" => "click", "id" => 99 }]).call }
  end
  def test_handoff_invoked
    calls = []
    hf = ->(a) { calls << a["reason"] }
    scout([{ "do" => "handoff", "reason" => "2fa" },
           { "do" => "done", "selectors" => F::Browser::SEL }], handoff: hf).call
    assert_equal ["2fa"], calls
  end
  def test_off_domain_after_click_raises
    @browser.mark_node = F::Node.new(on_click: -> { @browser.url = "https://evil.example/" })
    assert_raises(P::PolicyError) { scout([{ "do" => "click", "id" => 0 }]).call }
  end
end
