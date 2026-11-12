# frozen_string_literal: true

require "json"

module Webhooks
  # Vipps callbacks for both rails: the ePayment webhook and the Recurring
  # agreement/charge events. Vipps signs callbacks with an authorization
  # header carrying the POS/Acquirer shared secret (VIPPS_WEBHOOK_AUTH),
  # compared constant-time; the poller remains the source of truth for
  # payment state, so a webhook only accelerates it.
  #
  # Vipps dashboard → callbacks:
  #   URL: https://<amber host>/webhooks/vipps
  #   Auth token → VIPPS_WEBHOOK_AUTH
  class VippsController < ActionController::Base
    skip_forgery_protection
    include Shared::WriteThrottle
    self.write_throttle_limit = 300

    def create
      return head :unauthorized unless authorized?

      payload = JSON.parse(request.raw_post)
      dispatch(payload)
      head :ok
    rescue JSON::ParserError
      head :bad_request
    rescue StandardError => e
      Rails.logger.error("[webhooks/vipps] #{e.class}: #{e.message}")
      head :unprocessable_entity
    end

    private

    def authorized?
      expected = ENV["VIPPS_WEBHOOK_AUTH"].to_s
      return false if expected.empty?

      ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.hexdigest(expected),
        Digest::SHA256.hexdigest(request.headers["Authorization"].to_s),
      )
    end

    def dispatch(payload)
      case payload["agreementId"]
      when String
        settle_agreement(payload)
      when nil
        accelerate_poll(payload)
      end
    end

    # An agreement event: activation, stop or expiry. The row copies the
    # state; the entitlement lives and dies with ACTIVE.
    def settle_agreement(payload)
      agreement = VippsAgreement.find_by(agreement_id: payload["agreementId"])
      return if agreement.nil?

      state = payload["status"].to_s.upcase
      agreement.update!(state:) if VippsAgreement::STATUSES.include?(state)
    end

    # A payment event: wake the poller now instead of at its next backoff.
    def accelerate_poll(payload)
      payment = VippsPayment.find_by(reference: payload["reference"])
      return if payment.nil? || payment.settled?

      Payments::PollVippsPaymentJob.perform_later(payment.id)
    end
  end
end
