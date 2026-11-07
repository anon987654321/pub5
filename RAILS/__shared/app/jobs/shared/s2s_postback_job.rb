# frozen_string_literal: true

require "net/http"
require "uri"

module Shared
  class S2sPostbackJob < ApplicationJob
    class RetryableResponse < StandardError; end

    queue_as :default
    retry_on Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET, RetryableResponse,
             wait: :polynomially_longer, attempts: 5

    MEDIAGO_URL = "https://sync.mediago.io/api/bidder/postback"
    REVCONTENT_URL = "https://trends.revcontent.com/api/v1/conversion.php"

    def perform(conversion_id)
      conversion = S2sConversion.find(conversion_id)
      attribution = S2sAttribution.find_by(user_id: conversion.user_id)
      return unless attribution

      results = conversion.postback_results.to_h.stringify_keys
      mediago_currency = ENV["MEDIAGO_CURRENCY"].to_s.strip.upcase
      if attribution.mediago_tracking_id.present? &&
         ENV["MEDIAGO_ACCOUNT_NAME"].present? &&
         mediago_currency.present? &&
         mediago_currency == conversion.currency.to_s.upcase &&
         !results.key?("mediago")
        results["mediago"] = dispatch(MEDIAGO_URL, {
          trackingid: attribution.mediago_tracking_id, conversiontype: 8,
          conversionprice: (conversion.amount_cents / 100.0).round(2),
          includeintotalconversion: 1, accountname: ENV.fetch("MEDIAGO_ACCOUNT_NAME")
        })
        conversion.update!(postback_results: results)
      end
      # Revcontent documents amount as a non-zero whole-dollar value. Do not
      # turn NOK/EUR/etc. into an apparent USD amount; no FX rate is available
      # here, and inventing one would corrupt the advertiser's ROAS.
      revcontent_amount = (conversion.amount_cents / 100.0).round
      if attribution.revcontent_rc_uuid.present? &&
         ENV["REVCONTENT_API_KEY"].present? &&
         conversion.currency.to_s.upcase == "USD" &&
         revcontent_amount.positive? &&
         !results.key?("revcontent")
        results["revcontent"] = dispatch(REVCONTENT_URL, {
          api_key: ENV.fetch("REVCONTENT_API_KEY"), rc_uuid: attribution.revcontent_rc_uuid,
          amount: revcontent_amount
        })
        conversion.update!(postback_results: results)
      end

      # No eligible/configured provider is not a failed delivery. Keep the row
      # queued so missing account configuration or currency can be corrected
      # without writing a false provider result.
      return conversion if results.empty?

      statuses = results.values.map { |result| result.fetch("code", 500) }
      state = if statuses.all? { |code| code.between?(200, 299) } then "sent"
              elsif statuses.any? { |code| code.between?(200, 299) } then "partial"
              else "failed"
              end
      conversion.update!(postback_results: results, status: state)
    end

    private

    def dispatch(endpoint, parameters)
      uri = URI(endpoint)
      uri.query = URI.encode_www_form(parameters)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Brgen-S2S-Attribution/1.0"
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 5) do |http|
        http.request(request)
      end
      code = response.code.to_i
      raise RetryableResponse, "S2S provider returned HTTP #{code}" if code == 429 || code >= 500

      { "code" => code }
    end
  end
end
