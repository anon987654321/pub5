# frozen_string_literal: true

require "json"
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
    BLOCKED_HOST_SUFFIXES = Shared::OutboundHttp::BLOCKED_HOST_SUFFIXES
    MAX_PINNED_HOSTS = 64
    MAX_PIN_ROUNDS = 8

    def self.call(url, schema:, hint: nil)
      raise ArgumentError, "scrape requires a public HTTP(S) URL" unless public_http_url?(url)
      raise LoadError, "gem install ferrum — required for Scrape.call" unless defined?(Ferrum::Browser)

      pins = {}
      root_host = URI.parse(url).hostname.downcase.delete_suffix(".")
      pins[root_host] = pinned_public_address!(root_host)
      rounds = 0

      loop do
        rounds += 1
        newly_pinned = []
        overflow_hosts = []
        browser = Ferrum::Browser.new(
          headless: true, timeout: 30,
          browser_options: {
            "host-resolver-rules" => host_resolver_rules(pins),
            "host-resolver-retry-attempts" => "0",
            "no-proxy-server" => nil
          }
        )
        begin
          # Chromium uses a fixed resolver table for this pass. The wildcard
          # ~NOTFOUND rule makes an unpinned hostname fail closed instead of
          # falling back to a fresh OS DNS lookup after Ruby approved it.
          browser.network.intercept
          browser.on(:request) do |request|
            if safe_non_network_scheme?(request.url)
              request.continue
              next
            end

            uri = URI.parse(request.url) rescue nil
            host = uri&.hostname.to_s.downcase.delete_suffix(".")
            if uri && public_browser_url?(uri) && pins.key?(host)
              request.continue
            elsif uri && public_browser_url?(uri) && !pins.key?(host) &&
                  pins.length < MAX_PINNED_HOSTS
              begin
                pins[host] = pinned_public_address!(host)
                newly_pinned << host
              rescue StandardError
                # Private, reserved or unresolvable request: abort it.
              end
              request.abort
            else
              overflow_hosts << host if uri && public_browser_url?(uri) && !pins.key?(host)
              request.abort
            end
          end

          begin
            browser.go_to(url)
          rescue StandardError
            raise unless newly_pinned.any?
          end
          browser.network.wait_for_idle(timeout: 10)
          raise ArgumentError, "scrape discovered more than #{MAX_PINNED_HOSTS} public hosts" unless overflow_hosts.empty?

          if newly_pinned.empty?
            html = browser.body
            png = browser.screenshot(encoding: :binary, full: true)
            return reason(url:, html:, png:, schema:, hint:)
          end
        ensure
          browser.quit
        end

        raise ArgumentError, "scrape did not converge on a fixed DNS map after #{MAX_PIN_ROUNDS} passes" if rounds >= MAX_PIN_ROUNDS
      end
    end

    # A browser cannot use Net::HTTP#ipaddr. Instead, Chromium receives explicit
    # host resolver rules for every hostname approved by the Ruby resolver, plus
    # a wildcard rule that prevents any second DNS lookup. SNI and Host still use
    # the URL hostname; only the TCP destination is substituted.
    def self.host_resolver_rules(pins)
      rules = pins.sort.filter_map do |host, address|
        raise ArgumentError, "invalid browser pin hostname: #{host}" unless Shared::OutboundHttp.valid_resolver_host?(host)

        ip = IPAddr.new(address)
        raise ArgumentError, "non-public browser pin refused: #{host}" if Shared::OutboundHttp.unsafe_ip?(ip)
        next if ip_literal_host?(host)

        destination = ip.ipv6? ? "[#{ip}]" : ip.to_s
        "MAP #{host} #{destination}"
      end
      (rules << "MAP * ~NOTFOUND").join(", ")
    end

    def self.pinned_public_address!(host)
      Shared::OutboundHttp.public_address!(host)
    end

    def self.ip_literal_host?(host)
      IPAddr.new(host.to_s)
      true
    rescue IPAddr::InvalidAddressError
      false
    end

    def self.public_browser_url?(uri)
      uri.is_a?(URI::HTTP) && uri.userinfo.nil? && uri.fragment.nil? &&
        !uri.hostname.to_s.empty? && Shared::OutboundHttp.valid_resolver_host?(uri.hostname)
    end

    def self.safe_non_network_scheme?(value)
      scheme = URI.parse(value.to_s).scheme.to_s.downcase
      %w[data blob about].include?(scheme)
    rescue URI::InvalidURIError
      false
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
