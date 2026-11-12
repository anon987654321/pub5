# frozen_string_literal: true

require "test_helper"

# The entitlement spine: a grant answers accessible_by? for exactly one
# subject until it expires, a PPV unlock is permanent, a retried webhook
# grants once, and the premium plan opens everything ticketed.
class EntitlementTest < ActiveSupport::TestCase
  def setup
    @owner = User.create!(email_address: "owner-#{SecureRandom.hex(4)}@example.no", password: "password123")
    @buyer = User.create!(email_address: "buyer-#{SecureRandom.hex(4)}@example.no", password: "password123")
    @post = @owner.posts.create!(body: "behind the paywall", price_minor: 4900, currency: "NOK")
  end

  test "a ppv post is gated and the author needs no unlock" do
    assert_predicate @post, :ppv?
    assert @post.accessible_by?(@owner)
    refute @post.accessible_by?(@buyer)
    refute @post.accessible_by?(nil)
  end

  test "a free post belongs to the public feed" do
    free = @owner.posts.create!(body: "for everyone")
    refute_predicate free, :ppv?
    assert free.accessible_by?(nil)
  end

  test "a grant opens exactly its subject and never expires" do
    @buyer.grant_entitlement!(subject: @post, source: "ppv")

    assert @post.accessible_by?(@buyer)
    other = @owner.posts.create!(body: "another paywall", price_minor: 100)
    refute other.accessible_by?(@buyer)
  end

  test "granting twice stores one row" do
    @buyer.grant_entitlement!(subject: @post, source: "ppv")
    @buyer.grant_entitlement!(subject: @post, source: "ppv")

    assert_equal 1, @buyer.entitlements.count
  end

  test "an expired grant answers no" do
    Entitlement.create!(user: @buyer, subject: @post, source: "live_ticket",
                        expires_at: 1.minute.ago)

    refute @post.accessible_by?(@buyer)
  end

  test "a plan-style grant needs a name and a subject row needs none" do
    named = Entitlement.new(user: @buyer, source: "subscription", entitlement_name: "amber_premium")
    assert named.valid?

    nameless = Entitlement.new(user: @buyer, source: "ppv")
    refute nameless.valid?
  end

  test "premium answers every gate" do
    Shared::BillingSubscription.create!(
      user: @buyer, plan_key: "amber_premium_monthly", status: "active",
      stripe_subscription_id: "sub_#{SecureRandom.hex(8)}",
    )

    assert @buyer.entitled_to?(@post)
    assert @buyer.entitled_to?(LiveStream.new(id: 1, ticketed: true))
  end
end
