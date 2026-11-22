# frozen_string_literal: true

module Payments
  # Confirms a Vipps ePayment by polling, per Vipps' own integration rule:
  # neither returnUrl nor a webhook alone is the truth. The job asks the API
  # on a short backoff until the payment settles, then either captures the
  # money fact and grants what it bought, or records the failure. AUTHORIZED
  # is not terminal - the capture follows it in the same run.
  class PollVippsPaymentJob < ApplicationJob
    queue_as :default

    MAX_ATTEMPTS = 12
    BASE_WAIT = 5.seconds

    def perform(payment_id, attempt: 1)
      payment = VippsPayment.find_by(id: payment_id)
      return if payment.nil? || payment.settled?

      state = Payments::VippsAdapter.payment_state(reference: payment.reference)
      apply_state(payment, state["state"].to_s)

      return if payment.settled?
      return if attempt >= MAX_ATTEMPTS

      Payments::PollVippsPaymentJob.set(wait: BASE_WAIT * attempt)
                                   .perform_later(payment.id, attempt: attempt + 1)
    rescue Payments::VippsClient::Error => e
      Rails.logger.warn("[vipps/poll] payment=#{payment_id} attempt=#{attempt}: #{e.message}")
      raise if attempt < MAX_ATTEMPTS && e.message.exclude?("HTTP 4")
    end

    private

    def apply_state(payment, state)
      payment.update!(state:) if payment.state != state && VippsPayment::STATUSES.include?(state)
      # AUTHORIZED holds the money but has not moved it; amber's goods unlock
      # the moment payment lands, so the capture follows in the same run.
      Payments::VippsAdapter.capture(reference: payment.reference, amount_minor: payment.amount_minor) if
        payment.state == "AUTHORIZED"
      return unless payment.captured?

      ApplicationRecord.transaction do
        PaymentTransaction.create!(
          user: payment.user, rail: "vipps", reference: payment.reference,
          amount_minor: payment.amount_minor, currency: payment.currency, state: "captured",
          purchasable: payment.purchasable,
        )
        grant_purchasable(payment)
      end
    end

    # What a captured charge buys, by the thing it was for: a Post's unlock,
    # a live stream's ticket. Anything else records the money fact and waits
    # for a buyer that names its own grant.
    def grant_purchasable(payment)
      subject = payment.purchasable
      return if subject.nil?

      source = subject.is_a?(LiveStream) ? "live_ticket" : "ppv"
      payment.user.grant_entitlement!(subject: subject, source:)
    end
  end
end
