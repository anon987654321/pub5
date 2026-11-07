# frozen_string_literal: true

require "net/http"
require "uri"

module Shared
  class S2sPostbackJob < ApplicationJob
    queue_as :default
    retry_on Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET,
             wait: :polynomially_longer, attempts: 5

    MEDIAGO_URL = "https://sync.mediago.io/api/bidder/postback"
    REVCONTENT_URL = "https://trends.revcontent.com/api/v1/conversion.php"

    def perform(conversion_id)
      conversion = S2sConversion.find(conversion_id)
      attribution = S2sAttribution.find_by(user_id: conversion.user_id)
      return unless attribution

      results = conversion.postback_results.to_h.stringify_keys
      if attribution.mediago_tracking_id.present? && ENV["MEDIAGO_ACCOUNT_NAME"].present? && !results.key?("mediago")
        results["mediago"] = dispatch(MEDIAGO_URL, {
          trackingid: attribution.mediago_tracking_id, conversiontype: 1,
          conversionprice: (conversion.amount_cents / 100.0).round(2),
          includeintotalconversion: 1, accountname: ENV.fetch("MEDIAGO_ACCOUNT_NAME")
        })
        conversion.update!(postback_results: results)
      end
      if attribution.revcontent_rc_uuid.present? && ENV["REVCONTENT_API_KEY"].present? && !results.key?("revcontent")
        results["revcontent"] = dispatch(REVCONTENT_URL, {
          api_key: ENV.fetch("REVCONTENT_API_KEY"), rc_uuid: attribution.revcontent_rc_uuid,
          amount: (conversion.amount_cents / 100.0).round(2)
        })
        conversion.update!(postback_results: results)
      end

      statuses = results.values.map { |result| result.fetch("code", 500) }
      state = if statuses.empty? then "failed"
              elsif statuses.all? { |code| code.between?(200, 299) } then "sent"
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
      { "code" => response.code.to_i }
    end
  end
end
