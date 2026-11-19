# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Master
  module Io
    class DynamicHttp
      TIER = :guarded
      NAME = "dynamic_http".freeze
      DESCRIPTION = "Call a configured HTTP endpoint from data/tools.dynamic.yml.".freeze
      TIMEOUT = 20
      MAX_BYTES = 32_000

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      def call(name:, params: {})
        Master::Ground::LawHandshake::Admission.require!
        defn = Io::DynamicTools.lookup(name)
        return Result.err("dynamic_http: unknown tool #{name}", category: :validation) unless defn
        if DynamicTools.elevated?(defn) && !Fiber[:master_elevated]
          return Result.err("dynamic_http: #{name} waits for an elevated session", category: :policy)
        end

        perm = @governor.permit?(NAME, TIER, "#{name} #{params}")
        return perm if perm.err?

        uri = resolve_and_validate_uri(defn, params)
        return uri if uri.is_a?(Result::Err)

        method = defn.fetch("method", "GET").to_s.upcase
        response = perform_request(uri, method, defn, params)

        text = response.body.to_s.byteslice(0, MAX_BYTES)
        @bus&.publish("tool:after", tool: NAME, dynamic: name, status: response.code.to_i)
        Result.ok("HTTP #{response.code}\n#{text}")
      rescue SocketError => e
        Result.err("dynamic_http: refused internal/reserved address (#{e.message})", category: :validation)
      rescue StandardError => e
        Result.err("dynamic_http: #{e.message}", category: :infrastructure)
      end

      def resolve_and_validate_uri(defn, params)
        url = interpolate(defn.fetch("url").to_s, params)
        uri = URI(url)
        return Result.err("dynamic_http: only clean HTTP(S) URLs on standard ports", category: :validation) unless SsrfGuard.valid_http_uri?(uri)

        uri
      end

      def perform_request(uri, method, defn, params)
        request = if %w[POST PUT PATCH].include?(method)
                    outbound = Net::HTTP.const_get(method.capitalize).new(uri.request_uri)
                    outbound["Content-Type"] = defn.fetch("content_type", "application/json")
                    outbound.body = build_body(defn, params)
                    outbound
                  else
                    Net::HTTP::Get.new(uri.request_uri)
                  end

        SsrfGuard.request(
          uri, request, max_bytes: MAX_BYTES, timeout: TIMEOUT * 2,
          open_timeout: TIMEOUT, read_timeout: TIMEOUT, write_timeout: TIMEOUT
        )
      end

      private

      # Params come from the model, so each value is escaped for the slot it
      # fills: a raw `&admin=1` in a query or a `"` in a JSON body would rewrite
      # the request around it.
      def interpolate(template, params, escape: :url)
        sym = params.transform_keys(&:to_sym)
        template.gsub(/\{(\w+)\}/) do
          value = sym[Regexp.last_match(1).to_sym].to_s
          case escape
          when :url then URI.encode_uri_component(value)
          when :json then JSON.generate(value)[1..-2]
          else URI.encode_www_form_component(value)
          end
        end
      end

      def build_body(defn, params)
        return JSON.generate(params) unless defn["body_template"]

        json = defn.fetch("content_type", "application/json").to_s.include?("json")
        interpolate(defn["body_template"].to_s, params, escape: json ? :json : :form)
      end
    end
  end
end
