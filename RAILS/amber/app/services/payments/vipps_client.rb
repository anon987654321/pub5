# frozen_string_literal: true

require "net/http"

module Payments
  # The thin Vipps MobilePay client. One reader of the base URL and keys, so
  # the adapter never touches the environment. Every mutating call carries a
  # caller-owned Idempotency-Key; Vipps answers 4010/4150 when a retry does
  # not repeat the same body, so the caller stores the key beside the request.
  class VippsClient
    Error = Class.new(StandardError)

    EPAYMENT_BASE = "https://api.vipps.no".freeze
    # The test environment is the default outside production; the operator's
    # env file names the real one with VIPPS_BASE_URL.
    TEST_BASE = "https://apitest.vipps.no".freeze

    class << self
      def configured? = [ merchant_serial_number, subscription_key ].all?(&:present?)

      def base_url = ENV["VIPPS_BASE_URL"].presence || (Rails.env.production? ? EPAYMENT_BASE : TEST_BASE)

      def merchant_serial_number = ENV["VIPPS_MSN"].to_s.strip

      def subscription_key = ENV["VIPPS_SUBSCRIPTION_KEY"].to_s.strip

      def client_id = ENV["VIPPS_CLIENT_ID"].to_s.strip

      def client_secret = ENV["VIPPS_CLIENT_SECRET"].to_s.strip

      def otp_credential = ENV["VIPPS_OTP_CREDENTIAL"].to_s.strip

      # An access token, held for the process briefly. Vipps tokens live
      # about an hour; the cache spares one call per charge burst.
      def access_token
        Rails.cache.fetch("vipps/access_token", expires_in: 30.minutes) { fetch_access_token }
      end

      # The one HTTP doors: POST and GET with the subscription key header on
      # every call and the bearer token where the endpoint wants one.
      def post_json(path, body, auth: true, idempotency_key: nil)
        request = Net::HTTP::Post.new(uri_for(path))
        request["Content-Type"] = "application/json"
        request["Ocp-Apim-Subscription-Key"] = subscription_key
        request["Authorization"] = "Bearer #{access_token}" if auth
        request["Idempotency-Key"] = idempotency_key if idempotency_key
        request.body = JSON.generate(body) if body
        send(request)
      end

      def get_json(path)
        request = Net::HTTP::Get.new(uri_for(path))
        request["Ocp-Apim-Subscription-Key"] = subscription_key
        request["Authorization"] = "Bearer #{access_token}"
        send(request)
      end

      private

      def fetch_access_token
        # Vipps issues the token from the client credentials; the post_json
        # door cannot fetch it (no token yet), so this call stands bare.
        request = Net::HTTP::Post.new(uri_for("accessToken/get"))
        request["client_id"] = client_id
        request["client_secret"] = client_secret
        request["Ocp-Apim-Subscription-Key"] = subscription_key
        token = send(request)["access_token"]
        return token if token.present?

        raise Error, "vipps: no access_token in reply"
      end

      def send(request)
        uri = request.uri
        reply = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
          http.request(request)
        end
        raise Error, "vipps: HTTP #{reply.code} from #{uri.path}" unless reply.is_a?(Net::HTTPSuccess)

        JSON.parse(reply.body)
      rescue JSON::ParserError
        raise Error, "vipps: unreadable JSON from #{uri.path}"
      end

      def uri_for(path)
        URI.join("#{base_url}/", path.delete_prefix("/"))
      end
    end
  end
end
