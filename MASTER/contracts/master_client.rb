# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "ipaddr"
require_relative "../lib/io/ssrf_guard"

module Contracts
  module MasterClient
    DEFAULT_TIMEOUT = 45

    module_function

    def configured?
      !token.nil?
    end

    def token
      value = ENV["MASTER_INGRESS_TOKEN"].to_s.strip
      value unless value.empty?
    end

    def base_url
      value = ENV["MASTER_WEB_URL"].to_s.strip.sub(%r{/\z}, "")
      value.empty? ? "http://127.0.0.1:53187" : value
    end

    class Client
      def initialize(base_url: Contracts::MasterClient.base_url, token: Contracts::MasterClient.token,
                     timeout: Contracts::MasterClient::DEFAULT_TIMEOUT)
        @base_url = base_url
        @token = token.to_s
        @timeout = timeout
      end

      def available?
        @token != "" && health.fetch("ok", false)
      rescue StandardError
        false
      end

      def health
        get("/ingress/health")
      end

      def turn(message, session_key: nil, channel: "rails")
        return { ok: false, error: "MASTER_INGRESS_TOKEN not configured", output: "" } if @token.empty?

        key = session_key.to_s.strip
        key = "rails:#{Process.pid}" if key.empty?
        post("/ingress/webhook/rails_master",
             { message: message.to_s, session_key: key, channel: channel.to_s })
      rescue StandardError => e
        { ok: false, error: e.message, output: "" }
      end

      def assist(prompt, domain: "general", session_key: nil)
        turn("[rails/#{domain}] #{prompt}", session_key:, channel: "rails-#{domain}")
      end

      private

      def get(path)
        uri = URI.join("#{@base_url}/", path.delete_prefix("/"))
        request(uri, Net::HTTP::Get.new(uri))
      end

      def post(path, body)
        uri = URI.join("#{@base_url}/", path.delete_prefix("/"))
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["Authorization"] = "Bearer #{@token}"
        req.body = JSON.generate(body)
        request(uri, req)
      end

      def request(uri, req)
        unless uri.userinfo.nil? && uri.fragment.nil?
          raise URI::InvalidURIError, "MASTER ingress URL credentials and fragments are refused"
        end

        res = if local_endpoint?(uri)
                http = Net::HTTP.new(uri.hostname, uri.port, nil)
                http.open_timeout = 5
                http.read_timeout = @timeout
                http.write_timeout = 5
                http.start { |connection| connection.request(req) }
              else
                unless uri.is_a?(URI::HTTPS) && uri.port == 443
                  raise URI::InvalidURIError, "hosted MASTER ingress requires HTTPS on port 443"
                end
                Master::Io::SsrfGuard.request(
                  uri, req, max_bytes: 2_000_000, timeout: @timeout,
                  open_timeout: 5, read_timeout: @timeout, write_timeout: 5
                )
              end
        raise Master::Io::SsrfGuard::ResponseTooLarge, "local MASTER ingress response exceeds 2 MB" if
          local_endpoint?(uri) && res.body.to_s.bytesize > 2_000_000

        parsed = JSON.parse(res.body.to_s).transform_keys(&:to_s)
        return { "ok" => false, "error" => parsed["error"] || "HTTP #{res.code}", "output" => "" } if res.code.to_i >= 400

        parsed
      rescue JSON::ParserError
        { "ok" => res.code.to_i < 400, "output" => res.body.to_s, "error" => nil }
      end

      def local_endpoint?(uri)
        return false unless uri.is_a?(URI::HTTP) && uri.scheme == "http"

        host = uri.hostname.to_s.downcase
        return true if host == "localhost"

        IPAddr.new(host).loopback?
      rescue IPAddr::InvalidAddressError
        false
      end
    end
  end
end
