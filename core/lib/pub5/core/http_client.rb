# frozen_string_literal: true
require "net/http"
require "uri"
require_relative "errors"

module Pub5
  module Core
    class HttpClient
      Response = Struct.new(:status, :headers, :body, keyword_init: true)

      def initialize(allowed_hosts:, open_timeout: 3, read_timeout: 15, max_bytes: 2_000_000)
        @allowed_hosts = Array(allowed_hosts).map { |host| host.to_s.downcase }.freeze
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @max_bytes = max_bytes
      end

      def get(url, headers: {})
        uri = URI.parse(url)
        raise Denied, "HTTPS is required" unless uri.is_a?(URI::HTTPS)
        raise Denied, "host is not allow-listed" unless @allowed_hosts.include?(uri.host.to_s.downcase)
        request = Net::HTTP::Get.new(uri.request_uri, headers)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: @open_timeout, read_timeout: @read_timeout) { |http| http.request(request) }
        body = response.body.to_s
        raise Denied, "response exceeds configured limit" if body.bytesize > @max_bytes
        raise Denied, "redirect requires an explicit new request" if response.is_a?(Net::HTTPRedirection)
        Response.new(status: response.code.to_i, headers: response.each_header.to_h.freeze, body: body.freeze)
      rescue URI::InvalidURIError => e
        raise Denied, e.message
      end
    end
  end
end
