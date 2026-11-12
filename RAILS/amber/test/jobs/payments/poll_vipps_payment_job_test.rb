# frozen_string_literal: true

require "test_helper"

module Payments
  # The poller is the truth: a webhook may wake it early, and it asks the API
  # until the payment names a terminal state.
  class PollVippsPaymentJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    def setup
      @buyer = User.create!(email_address: "poll-#{SecureRandom.hex(4)}@example.no", password: "password123")
      @seller = User.create!(email_address: "p-#{SecureRandom.hex(4)}@example.no", password: "password123")
      @post = @seller.posts.create!(body: "locked", price_minor: 4900, currency: "NOK")
      @payment = VippsPayment.create!(user: @buyer, reference: "ref-poll", amount_minor: 4900,
                                      idempotency_key: "k-poll", purchasable: @post)
    end

    test "an unknown payment id is nobody's problem" do
      assert_nothing_raised { PollVippsPaymentJob.perform_now(-1) }
    end

    test "a settled payment is never re-polled" do
      @payment.update!(state: "CAPTURED")

      assert_no_enqueued_jobs do
        VippsAdapter.stub(:payment_state, ->(reference:) { flunk("must not ask") }) do
          PollVippsPaymentJob.perform_now(@payment.id)
        end
      end
    end

    test "a webhook wake enqueues the poll for a pending payment" do
      controller = Webhooks::VippsController.new

      assert_enqueued_with(job: PollVippsPaymentJob) do
        controller.send(:accelerate_poll, { "reference" => @payment.reference })
      end
    end

    test "a webhook for a settled payment wakes nobody" do
      @payment.update!(state: "CAPTURED")

      assert_no_enqueued_jobs do
        Webhooks::VippsController.new.send(:accelerate_poll, { "reference" => @payment.reference })
      end
    end
  end
end
