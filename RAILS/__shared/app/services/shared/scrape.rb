# frozen_string_literal: true

require "json"
require "ipaddr"
require "socket"
require "ipaddr"
require "socket"
require "uri"
require_relative "outbound_http"

begin
  require "ferrum"
rescue LoadError
  nil
end

module Shared
  class Scrape
    MODEL = ENV.fetch("SCRAPE_MODEL", Shared::Llm::DEFAULT_MODEL)
    HTML_MAX = 60_000
    BLOCKED_HOST_SUFFIXES = %w[.localhost .local .internal .home.arpa .onion].freeze
    BLOCKED_HOST_SUFFIXES = Shared::OutboundHttp::BLOCKED_HOST_SUFFIXES


    def self.call(url, schema:, hint: nil)
      raise ArgumentError, "scrape requires a public HTTP(S) URL" unless public_http_url?(url)
      raise LoadError, "gem install ferrum — required for Scrape.call" unless defined?(Ferrum::Browser)

      # Keep Chromium's renderer sandbox enabled when processing untrusted pages.
      # Run the scraper as an unprivileged account; do not trade isolation for
      # convenience by passing Chromium's --no-sandbox switch.
      browser = Ferrum::Browser.new(headless: true, timeout: 30)
      begin
        # A public page may redirect, load scripts, or embed images from another
        # origin. Check each browser request, not just the first URL, so a redirect
        # cannot turn a public seed URL into a request to localhost or cloud metadata.
        browser.network.intercept
        browser.on(:request) do |request|
          if safe_request_url?(request.url)
            request.continue
          else
            request.abort
          end
        end
        browser.go_to(url)
        browser.network.wait_for_idle(timeout: 10)
        html = browser.body
        png = browser.screenshot(encoding: :binary, full: true)
        reason(url:, html:, png:, schema:, hint:)
      ensure
        browser.quit
      end
    end

    # Only public HTTP(S) targets are scrape entrypoints. Resolve names here and
    # at every intercepted request; any private/reserved answer fails closed.
    # This application-level guard complements, but does not replace, host firewalling.
    def self.public_http_url?(value, resolver: ->(host) { Shared::OutboundHttp.resolve_addresses(host) })
      uri = URI.parse(value.to_s)
      return false unless %w[http https].include?(uri.scheme&.downcase)
      return false if uri.userinfo || uri.fragment || uri.hostname.to_s.empty?

      host = uri.hostname.downcase.delete_suffix(".")
      return false unless Shared::OutboundHttp.valid_resolver_host?(host)
      return false if host == "localhost" || BLOCKED_HOST_SUFFIXES.any? { |suffix| host.end_with?(suffix) }

      addresses = begin
        [IPAddr.new(host).to_s]
      rescue IPAddr::InvalidAddressError
        Array(resolver.call(host))
      end
      addresses.any? && addresses.all? { |address| !Shared::OutboundHttp.unsafe_ip?(address) }
    rescue URI::InvalidURIError, SocketError, ArgumentError
      false
    end

    def self.safe_request_url?(value, resolver: ->(host) { Shared::OutboundHttp.resolve_addresses(host) })
      uri = URI.parse(value.to_s)
      return true if %w[data blob about].include?(uri.scheme&.downcase)

      public_http_url?(value, resolver:)
    rescue URI::InvalidURIError, ArgumentError
      false
    end

    def self.reason(url:, html:, png:, schema:, hint:)
      prompt = <<~TXT
        Source: #{url}
        Extract every listed item on the page as JSON. Use the screenshot to read visual layout (cards, sponsored banners, hidden overlays); use the HTML for exact text and links.
        #{hint}
        Reply with one JSON object: {"items":[{#{schema.join(', ')}}, ...]}.
        HTML (truncated to #{HTML_MAX} bytes):
        #{html.byteslice(0, HTML_MAX)}
      TXT
      llm = Shared::Llm.new(model: MODEL)
      content = llm.ask(prompt, with: llm.attachment(png, filename: "page.png"))
      JSON.parse(content).fetch("items", [])
    end
  end
end
