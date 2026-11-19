#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "ipaddr"
require_relative "../MASTER/lib/io/ssrf_guard"
require "optparse"
require "uri"

module Operator
  class PtrOpenbsdAmsterdam
    IPV4_ENDPOINT = "http://ptr4.openbsd.amsterdam"
    IPV6_ENDPOINT = "http://ptr6.openbsd.amsterdam"

    def initialize(ip:, hostname:, apply: false)
      @ip = ip
      @hostname = hostname
      @apply = apply
    end

    def call
      validate!
      uri, request = build_request

      unless apply
        puts JSON.pretty_generate(
          dry_run: true,
          endpoint: endpoint,
          ip: ip,
          hostname: hostname,
          method: request.method,
          note: "Set APPLY_PTR=1 to send this request."
        )
        return true
      end

      expected_host = ip.include?(":") ? "ptr6.openbsd.amsterdam" : "ptr4.openbsd.amsterdam"
      unless uri.is_a?(URI::HTTP) && uri.scheme == "http" && uri.port == 80 && uri.host == expected_host
        raise URI::InvalidURIError, "PTR service endpoint is outside the configured OpenBSD service"
      end
      response = Master::Io::SsrfGuard.request(
        uri, request, max_bytes: 64_000, timeout: 15,
        open_timeout: 5, read_timeout: 15, write_timeout: 5
      )

      puts response.body unless response.body.to_s.empty?
      response.is_a?(Net::HTTPSuccess)
    end

    private

    attr_reader :ip, :hostname, :apply

    def endpoint
      ip.include?(":") ? IPV6_ENDPOINT : IPV4_ENDPOINT
    end

    def build_request
      uri = URI(endpoint)
      uri.query = URI.encode_www_form(ip: ip, hostname: hostname)
      [uri, Net::HTTP::Post.new(uri)]
    end

    def validate!
      raise ArgumentError, "hostname must end with a dotless DNS name" unless hostname.match?(/\A[a-z0-9.-]+\.[a-z]{2,}\z/i)
      address = IPAddr.new(ip)
      raise ArgumentError, "refusing a non-public PTR target" if Master::Io::SsrfGuard.blocked_ip?(address)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {
    apply: ENV["APPLY_PTR"] == "1",
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby OPENBSD/ptr_openbsd_amsterdam.rb --ipv4 IP --hostname NAME"
    opts.on("--ipv4 IP", "IPv4 address") { |value| options[:ip] = value }
    opts.on("--ipv6 IP", "IPv6 address") { |value| options[:ip] = value }
    opts.on("--hostname NAME", "PTR hostname, e.g. ns.brgen.no") { |value| options[:hostname] = value }
  end

  parser.parse!

  unless options[:ip] && options[:hostname]
    warn parser
    exit 64
  end

  ok = Operator::PtrOpenbsdAmsterdam.new(
    ip: options.fetch(:ip),
    hostname: options.fetch(:hostname),
    apply: options.fetch(:apply)
  ).call

  exit(ok ? 0 : 1)
end
