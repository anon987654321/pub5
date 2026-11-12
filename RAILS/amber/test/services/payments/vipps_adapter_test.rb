# frozen_string_literal: true

require "test_helper"

module Payments
  # The Vipps rail, with the network stubbed at the client door: the charge
  # row exists before the call, the poller asks the API until the payment
  # settles, AUTHORIZED captures, a capture grants what the charge bought.
  class VippsAdapterTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    def setup
      @buyer = User.create!(email_address: "vipps-#{SecureRandom.hex(4)}@example.no", password: "password123")
      @seller = User.create!(email_address: "s-#{SecureRandom.hex(4)}@example.no", password: "password123")
      @post = @seller.posts.create!(body: "locked", price_minor: 4900, currency: "NOK")
    end

    test "an unconfigured client refuses to charge rather than half-charging" do
      VippsClient.stub(:configured?, false) do
        assert_raises(VippsAdapter::Error) do
          VippsAdapter.create_one_off_charge(user: @buyer, amount_minor: 4900, purchasable: @post,
                                             description: "unlock")
        end
      end
    end

    test "a charge creates its row, asks Vipps and enqueues the poller" do
      stub_client(post: { "epayment/v1/payments" => { "reference" => "r", "status" => "CREATED" } }) do
        assert_enqueued_with(job: PollVippsPaymentJob) do
          VippsAdapter.create_one_off_charge(user: @buyer, amount_minor: 4900, purchasable: @post,
                                             description: "unlock")
        end
      end

      payment = VippsPayment.sole
      assert_equal 4900, payment.amount_minor
      assert_equal "Post", payment.purchasable_type
      assert_equal @post.id, payment.purchasable_id
      assert_equal "CREATED", payment.state
    end

    test "a recurring agreement stores the id Vipps answered with" do
      stub_client(post: { "recurring/v3/agreements" => { "agreementId" => "agr-9", "status" => "PENDING" } }) do
        agreement = VippsAdapter.create_recurring_agreement(
          user: @buyer, amount_minor: 7900, entitlement_name: "amber_premium",
          merchant_agreement_url: "https://amberapp.art/billing",
        )

        assert_equal "agr-9", agreement.agreement_id
        assert_equal "PENDING", agreement.state
        assert_equal "amber_premium", agreement.entitlement_name
      end
    end

    private

    # Point the client's HTTP door at a table of canned replies; the adapter's
    # behaviour is what is under test, not Faraday's.
    def stub_client(post: {})
      VippsClient.stub(:configured?, true) do
        VippsClient.stub(:post_json,
                         ->(path, _body, auth: true, idempotency_key: nil) { post.fetch(path) }) do
          yield
        end
      end
    end
  end
end
