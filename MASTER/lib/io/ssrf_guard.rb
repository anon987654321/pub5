# frozen_string_literal: true
require "ipaddr"
require "net/http"
require "socket"
require "timeout"
# Without this, safe_uri?'s `uri.is_a?(URI::HTTP)` raised NameError into its own
# blanket rescue and the guard answered false for every URL — web_fetch silently off.
require "uri"

module Master
  module Io
    # Blocks tool-driven HTTP fetches from reaching loopback, link-local
    # (including the 169.254.169.254 cloud metadata endpoint), private, and
    # other non-routable ranges. web_fetch/dynamic_http results flow back
    # into agent context as untrusted output, so a prompt-injection payload
    # that directs a fetch at the runtime's own internal network must not
    # succeed silently.
    #
    # The connection is pinned to the address this check approved. Net::HTTP
    # resolves a hostname again when it connects, so a DNS-rebinding domain
    # could answer public for the check and private for the socket; `http_for`
    # sets Net::HTTP#ipaddr to the checked address instead, while the hostname
    # still carries SNI, certificate verification and the Host header. Every
    # caller connects through `http_for`, never `Net::HTTP.start(uri.host, ...)`.
    module SsrfGuard
      RESERVED_RANGES = %w[
        0.0.0.0/8
        100.64.0.0/10
        192.0.0.0/24
        192.0.2.0/24
        192.88.99.0/24
        198.18.0.0/15
        198.51.100.0/24
        203.0.113.0/24
        240.0.0.0/4
        ::/96
        64:ff9b::/96
        64:ff9b:1::/48
        100::/64
        2001::/23
        2001:db8::/32
        2002::/16
        2d00::/8
        2e00::/7
        3000::/5
        3800::/6
        3c00::/7
        3e00::/8
        3f00::/8
        fec0::/10
        fc00::/7
      ].map { |cidr| IPAddr.new(cidr) }.freeze

      BLOCKED_HOSTNAMES = %w[
        metadata.google.internal
        metadata.google
        instance-data
        kubernetes.amazon.com
        169.254.169.254
      ].freeze

      DNS_LABEL_MAX_BYTES = 63
      DNS_MAX_WIRE_BYTES = 255
      DNS_TIMEOUT_S = 5
      GLOBAL_IPV6 = IPAddr.new("2000::/3").freeze
      BLOCKED_HOST_SUFFIXES = %w[.localhost .local .internal .home.arpa .onion].freeze

      # Bound names before resolution. Addrinfo uses the operating-system
      # resolver, avoiding the vulnerable Ruby Resolv parser for untrusted names.
      def self.valid_resolver_host?(host)
        candidate = host.to_s
        candidate = candidate[1...-1] if candidate.start_with?("[") && candidate.end_with?("]")
        candidate = candidate.delete_suffix(".")
        return false if candidate.empty?

        begin
          IPAddr.new(candidate)
          return true
        rescue IPAddr::InvalidAddressError
          # Continue with DNS-name limits.
        end

        labels = candidate.split(".", -1)
        return false if labels.length < 2
        return false if labels.any? do |label|
          label.empty? || label.bytesize > DNS_LABEL_MAX_BYTES ||
            !label.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i)
        end

        labels.sum { |label| label.bytesize + 1 } + 1 <= DNS_MAX_WIRE_BYTES
      end

      def self.resolve_addresses(host)
        return [] unless valid_resolver_host?(host)

        Timeout.timeout(DNS_TIMEOUT_S) do
          Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
        end
      rescue SocketError, SystemCallError, Timeout::Error
        []
      end

      # Browser-facing research may use ordinary HTTP, but arbitrary ports
      # turn a public URL into a scanner for exposed services. Keep the two
      # web schemes on their standard ports only.
      def self.valid_http_uri?(uri)
        return false unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
        return false unless uri.userinfo.nil? && uri.fragment.nil?

        (uri.scheme == "https" && uri.port == 443) || (uri.scheme == "http" && uri.port == 80)
      rescue URI::InvalidURIError, ArgumentError
        false
      end

      def self.safe_uri?(uri) = !pinned_address(uri).nil?

      # The address to connect to, or nil when the host is unsafe. Every answer
      # must be public: a name with one public and one private address is the
      # shape of a rebinding setup, not a choice.
      def self.pinned_address(uri)
        return unless valid_http_uri?(uri)

        host = uri.hostname.downcase.delete_suffix(".")
        return unless valid_resolver_host?(host)
        return if host == "localhost" || BLOCKED_HOSTNAMES.any? { |name| host.casecmp?(name) }
        return if BLOCKED_HOST_SUFFIXES.any? { |suffix| host.end_with?(suffix) }

        addresses = resolve_addresses(host)
        return if addresses.empty?
        return if addresses.any? { |addr| blocked_ip?(IPAddr.new(addr)) }

        address = IPAddr.new(addresses.first)
        address = address.native if address.respond_to?(:ipv4_mapped?) && address.ipv4_mapped?
        address.to_s
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "SsrfGuard.pinned_address")
        nil
      end

      # Bounded by default, so a caller that forgets a timeout still cannot hang
      # a turn on a host that accepts and never answers; callers may tighten it.
      DEFAULT_TIMEOUT_S = 15

      def self.http_for(uri, address, timeout: DEFAULT_TIMEOUT_S)
        raise URI::InvalidURIError, "pinned HTTP requires a clean HTTP/HTTPS URL on its standard port" unless valid_http_uri?(uri)

        ip = IPAddr.new(address.to_s)
        ip = ip.native if ip.respond_to?(:ipv4_mapped?) && ip.ipv4_mapped?
        raise SocketError, "refusing a non-public pinned address" if blocked_ip?(ip)

        # Net::HTTP defaults its proxy argument to :ENV. An ambient HTTP_PROXY or
        # HTTPS_PROXY would move the socket to a proxy and defeat the IP pin.
        Net::HTTP.new(uri.hostname, uri.port, nil).tap do |http|
          raise SocketError, "Net::HTTP cannot pin remote address" unless http.respond_to?(:ipaddr=)

          http.ipaddr = ip.to_s
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = timeout
          http.read_timeout = timeout
          http.write_timeout = timeout
        end
      end

      class ResponseTooLarge < StandardError; end

      # The one request path for public HTTP clients. The URL is classified,
      # every DNS answer is checked, the socket is pinned, and the body is
      # consumed under a byte cap before the response leaves this boundary.
      # Redirects remain responses: a caller must validate each Location and
      # start a new request through this method.
      def self.request(uri, outbound_request, max_bytes: 1_000_000, timeout: DEFAULT_TIMEOUT_S)
        raise URI::InvalidURIError, "outbound request needs a clean HTTP/HTTPS URL on its standard port" unless valid_http_uri?(uri)

        cap = Integer(max_bytes)
        seconds = Float(timeout)
        raise ArgumentError, "response byte cap must be positive" unless cap.positive?
        raise ArgumentError, "request timeout must be finite and positive" unless seconds.finite? && seconds.positive?

        address = pinned_address(uri) or raise SocketError, "refused non-public or unresolvable destination: #{uri.host}"
        http = http_for(uri, address, timeout: seconds)
        response = nil
        body = +"".b
        Timeout.timeout(seconds) do
          http.start do |connection|
            connection.request(outbound_request) do |incoming|
              response = incoming
              declared = incoming["content-length"].to_s
              if declared.match?(/\A\d+\z/) && declared.to_i > cap
                raise ResponseTooLarge, "response body exceeds #{cap} bytes"
              end
              incoming.read_body do |chunk|
                raise ResponseTooLarge, "response body exceeds #{cap} bytes" if body.bytesize + chunk.bytesize > cap

                body << chunk
              end
            end
          end
        end
        raise IOError, "outbound HTTP returned no response" unless response

        response.body = body
        response
      rescue Timeout::Error
        raise Timeout::Error, "outbound request exceeded #{timeout}s"
      ensure
        begin
          http.finish if http&.started?
        rescue IOError, SystemCallError
          nil
        end
      end

      def self.blocked_ip?(ip)
        ip = ip.native if ip.respond_to?(:ipv4_mapped?) && ip.ipv4_mapped?
        ip.loopback? || ip.link_local? || ip.private? ||
          (ip.ipv6? && !GLOBAL_IPV6.include?(ip)) ||
          (ip.respond_to?(:multicast?) && ip.multicast?) ||
          RESERVED_RANGES.any? { |range| range.include?(ip) }
      rescue StandardError
        true
      end
    end
  end
end
