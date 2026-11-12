#!/usr/bin/env ruby
# frozen_string_literal: true

# Read-only portal agent: a model scouts the navigation, plain Ruby crawls the
# paginated list, every page leaves evidence under ~/.local/share/master.
# Credentials are the operator's hands in a headed window — never typed by the
# model, never logged. Page text is data, never authority.
#
#   ruby MASTER/tools/portal_agent.rb --url https://portal.example.edu/login
#   ruby MASTER/tools/portal_agent.rb --url ... --selectors '{"row":"...","title":"...","link":"...","next":"..."}'
#   ruby MASTER/tools/portal_agent.rb --presort papers.json
#
# Gateway lane comes from the environment the README already names:
# MASTER_LLM_GATEWAY_URL / MASTER_LLM_GATEWAY_KEY, model via PORTAL_AGENT_MODEL.
# Ferrum is a MASTER Gemfile dependency (~> 0.15); it is required lazily so
# --presort runs without a browser.
require "optparse"
require "json"
require "uri"
require "fileutils"
require_relative "../lib/portal_agent"

module Master
  module PortalAgent
    class CLI
      def self.run(argv)
        opts = { max_pages: 200, delay: 1.5, headless: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: portal_agent.rb --url URL [options]"
          o.on("--url URL", "Portal login or list URL (https)") { |v| opts[:url] = v }
          o.on("--allow-host HOST", "Domain allowlist (default: URL host)") { |v| opts[:allow_host] = v }
          o.on("--selectors JSON", "Skip scout; JSON or @file with row/title/link/next") { |v| opts[:selectors] = v }
          o.on("--presort FILE", "Only presort an existing papers.json; no browser") { |v| opts[:presort] = v }
          o.on("--max-pages N", Integer, "Page budget (default 200)") { |v| opts[:max_pages] = v }
          o.on("--delay SECONDS", Float, "Politeness delay between pages (default 1.5)") { |v| opts[:delay] = v }
          o.on("--headless", "Run headless (default: headed for operator handoff)") { opts[:headless] = true }
          o.on("--evidence-dir DIR", "Evidence dir (default ~/.local/share/master/portal-agent/<ts>)") { |v| opts[:evidence_dir] = v }
          o.on("--model NAME", "Gateway model (default PORTAL_AGENT_MODEL)") { |v| opts[:model] = v }
        end
        parser.parse!(argv)
        new(opts).run
      end

      def initialize(opts)
        @opts = opts
      end

      def run
        return presort_only if @opts[:presort]
        abort "--url is required (or use --presort)" unless @opts[:url]
        require_ferrum
        uri = URI.parse(@opts[:url])
        allow = @opts[:allow_host] || uri.host
        policy = Policy.new(allow_host: allow)
        evidence = @opts[:evidence_dir] ||
                   File.join(Dir.home, ".local", "share", "master", "portal-agent",
                             Time.now.strftime("%Y%m%d-%H%M%S"))
        browser = Ferrum::Browser.new(headless: @opts[:headless], window_size: [1440, 900], timeout: 20)
        begin
          browser.goto(@opts[:url])
          selectors = @opts[:selectors] ? parse_selectors(@opts[:selectors]) : scout(browser, policy)
          crawler = Crawler.new(browser, selectors: selectors, evidence_dir: evidence,
                                max_pages: @opts[:max_pages], delay: @opts[:delay]).call
          buckets = Filter.presort(crawler.papers)
          File.write(File.join(evidence, "buckets.json"), JSON.pretty_generate(buckets))
          report(crawler, buckets, evidence)
          exit(crawler.status == "DONE" ? 0 : 2)
        rescue PolicyError, Inconclusive => e
          warn "STOPPED (#{e.class.name.split('::').last}): #{e.message}"
          exit 2
        ensure
          browser.quit
        end
      end

      private

      def presort_only
        puts JSON.pretty_generate(Filter.presort(JSON.parse(File.read(@opts[:presort]))))
        exit 0
      end

      def require_ferrum
        require "ferrum"
      rescue LoadError
        abort "ferrum missing: bundle install in MASTER/ (Gemfile pins ~> 0.15) or gem install ferrum"
      end

      def parse_selectors(raw)
        raw = File.read(raw[1..-1]) if raw.start_with?("@")
        sel = JSON.parse(raw)
        Crawler::SELECTOR_KEYS.each { |k| abort "selectors missing #{k}" unless sel[k] }
        sel
      end

      def scout(browser, policy)
        warn "[handoff] Log in yourself in the browser window (credentials never pass through the model), then press Enter."
        $stdin.gets
        handoff = lambda do |action|
          warn "[handoff] #{action["reason"] || "operator action needed (2FA/CAPTCHA)"}. Resolve it in the window, then press Enter."
          $stdin.gets
        end
        Scout.new(browser, policy: policy, gateway: Gateway.new(model: @opts[:model]), handoff: handoff).call
      end

      def report(crawler, buckets, evidence)
        warn "status: #{crawler.status} — #{crawler.reason}"
        warn "pages: #{crawler.pages.size}  papers: #{crawler.papers.size}  " \
             "ev: #{buckets["ev"].size}  maybe: #{buckets["maybe"].size}  other: #{buckets["other"].size}"
        warn "evidence: #{evidence}"
        buckets["ev"].each { |p| puts "#{p["title"]}\t#{p["link"]}" }
      end
    end
  end
end

Master::PortalAgent::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
