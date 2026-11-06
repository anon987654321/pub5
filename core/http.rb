# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Core
  # The one HTTP client. pub4 had 23 files calling Net::HTTP each its own way;
  # here there is one request method with one timeout policy, and a reply is a
  # plain value. TLS is verified; there is no switch to turn that off.
  module HTTP
    Reply = Data.define(:status, :headers, :body) do
      def ok? = status.between?(200, 299)
      def json = JSON.parse(body)
    end

    METHODS = {
      get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put,
      patch: Net::HTTP::Patch, delete: Net::HTTP::Delete, head: Net::HTTP::Head
    }.freeze

    module_function

    def request(method, url, headers: {}, body: nil, timeout: 30)
      uri = URI(url)
      raise Refusal.new(:net, url, "only http and https") unless %w[http https].include?(uri.scheme)

      klass = METHODS.fetch(method.to_sym) { raise Refusal.new(:net, url, "unknown method #{method}") }
      req = klass.new(uri)
      headers.each { |k, v| req[k] = v }
      req.body = body.is_a?(String) || body.nil? ? body : JSON.generate(body)
      req["content-type"] ||= "application/json" if body && !body.is_a?(String)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: timeout, read_timeout: timeout, write_timeout: timeout) do |http|
        res = http.request(req)
        Reply.new(status: res.code.to_i, headers: res.each_header.to_h, body: res.body.to_s)
      end
    end
  end
end
