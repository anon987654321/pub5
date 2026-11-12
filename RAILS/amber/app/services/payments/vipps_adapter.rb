# frozen_string_literal: true

module Payments
  # The Vipps rail, as the adapter behind PaymentTransaction. Two doors:
  # ePayment for one-off charges (a PPV unlock, a live ticket) and Recurring
  # for the monthly agreement that carries Amber Premium without Stripe.
  #
  # Vipps' own integration rule: a webhook or a returnUrl is an accelerant,
  # never the truth. The polling job confirms every payment's terminal state
  # by asking GET /epayment/v1/payments/{reference}.
  class VippsAdapter
    Reference = Data.define(:value) do
      def to_s = value
    end

    class << self
      # One-off charge. Stores the pending row first, asks Vipps second, and
      # enqueues the poller third - a crashed call after the row exists is a
      # payment the poller still finds.
      def create_one_off_charge(user:, amount_minor:, purchasable: nil, description:)
        raise Error, "vipps: client not configured" unless VippsClient.configured?

        reference = SecureRandom.hex(16)
        idempotency_key = SecureRandom.uuid
        payment = VippsPayment.create!(
          user:, reference:, amount_minor:, purchasable:,
          idempotency_key:, state: "CREATED",
        )

        VippsClient.post_json(
          "epayment/v1/payments",
          payment_body(user:, payment:, description:),
          idempotency_key:,
        )
        Payments::PollVippsPaymentJob.perform_later(payment.id)
        payment
      end

      # The poller's confirmation read.
      def payment_state(reference:) = VippsClient.get_json("epayment/v1/payments/#{reference}")

      # Capture an authorized charge. amber's goods are delivered at once, so
      # capture follows authorization immediately.
      def capture(reference:, amount_minor:)
        VippsClient.post_json(
          "epayment/v1/payments/#{reference}/capture",
          { amount: { currency: "NOK", value: amount_minor } },
          idempotency_key: "capture-#{reference}",
        )
      end

      # A fixed-interval agreement for one entitlement name. The customer
      # approves in the Vipps app; the activation arrives on the callback and
      # the agreement's own poll/webhook flips the row to ACTIVE.
      def create_recurring_agreement(user:, amount_minor:, entitlement_name:, merchant_agreement_url:)
        raise Error, "vipps: client not configured" unless VippsClient.configured?

        idempotency_key = SecureRandom.uuid
        reply = VippsClient.post_json(
          "recurring/v3/agreements",
          {
            currency: "NOK",
            interval: "MONTH",
            pricing: { type: "FIXED_PRICE", amount: amount_minor },
            productName: entitlement_name,
            merchantAgreementUrl: merchant_agreement_url,
            initialCharge: nil,
          }.compact,
          idempotency_key:,
        )
        VippsAgreement.create!(
          user:, agreement_id: reply.fetch("agreementId"),
          entitlement_name:, amount_minor:, state: reply.fetch("status", "PENDING"),
        )
      end

      # The next charge against a live agreement; a successful charge extends
      # the entitlement window it carries.
      def charge_agreement(agreement)
        VippsClient.post_json(
          "recurring/v3/agreements/#{agreement.agreement_id}/charges",
          { amount: { currency: agreement.currency, value: agreement.amount_minor },
            description: agreement.entitlement_name },
          idempotency_key: "charge-#{agreement.agreement_id}-#{Date.current.iso8601}",
        )
      end

      private

      def payment_body(user:, payment:, description:)
        {
          amount: { currency: payment.currency, value: payment.amount_minor },
          reference: payment.reference,
          paymentDescription: description.to_s[0, 100],
          paymentMethod: { type: "WALLET" },
          # amber holds no phone numbers, so the customer confirms in the Vipps
          # app through the return flow instead of a push to one number.
          returnUrl: Rails.application.routes.url_helpers.billing_url,
        }.compact
      end
    end

    Error = VippsClient::Error
  end
end
