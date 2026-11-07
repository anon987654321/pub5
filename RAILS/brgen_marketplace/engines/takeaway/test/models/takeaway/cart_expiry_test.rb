# frozen_string_literal: true

require "test_helper"

# The `takeaway_cart_expiry` convergence workstream: an unconfirmed cart has a
# 45-minute deadline, and `expire_stale_pending!` — the sweep job's engine — is
# the clock that turns a lapsed pending cart into a cancelled row through the
# same transition a manual cancel uses, so the kitchen and the reader are told
# through the notification path rather than by a status that changed behind
# their backs. Everything the sweep must leave alone is asserted to stay.
class Takeaway::CartExpiryTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(email_address: "expiry@brgen.no", password: "password123", city: @city)
    @buyer = User.strict_loading(false).create!(email_address: "cartexpiry@brgen.no", password: "password123", city: @city)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a pending cart past its deadline is cancelled by the sweep" do
    ActsAsTenant.with_tenant(@city) do
      kitchen = kitchen_with_cart
      @cart.update_columns(expires_at: cart_deadline_minutes.minutes.ago)

      Takeaway::Order.expire_stale_pending!

      assert_equal "cancelled", @cart.reload.status,
                   "a lapsed cart no longer reads as pending to the kitchen's order list"
    end
  end

  test "a pending cart still inside its deadline is left open" do
    ActsAsTenant.with_tenant(@city) do
      kitchen_with_cart

      Takeaway::Order.expire_stale_pending!

      assert_equal "pending", @cart.reload.status, "45 minutes of deciding is the promise"
    end
  end

  # The kitchen must not be cancelled out of a sale because the cart it
  # confirmed carried an old deadline: only "pending" expires.
  test "an order the kitchen confirmed is never expired by the sweep" do
    ActsAsTenant.with_tenant(@city) do
      kitchen_with_cart
      @cart.confirm!

      assert_equal "confirmed", @cart.reload.status
      @cart.update_columns(expires_at: cart_deadline_minutes.minutes.ago)
      Takeaway::Order.expire_stale_pending!

      assert_equal "confirmed", @cart.reload.status,
                   "a confirmed order owes the kitchen its preparation, not a deadline"
    end
  end

  # A row with no deadline is outside the contract: `unexpired` says so, and
  # the sweep's scope must agree with the readers or a cart visible as open
  # would still be cancelled.
  test "a pending cart with no deadline is not expired" do
    ActsAsTenant.with_tenant(@city) do
      kitchen_with_cart
      @cart.update_columns(expires_at: nil)

      Takeaway::Order.expire_stale_pending!

      assert_equal "pending", @cart.reload.status, "no deadline stated, no area claimed"
    end
  end

  # The point of cancel! over update_column: the cancelled cart appears through
  # the same notification path a manual cancel takes.
  test "the expired cart is told about through the notification path" do
    ActsAsTenant.with_tenant(@city) do
      kitchen_with_cart
      @cart.update_columns(expires_at: cart_deadline_minutes.minutes.ago)

      Takeaway::Order.expire_stale_pending!

      # Engine tests run inside the brgen app, whose notification class is the
      # top-level Notification with the title/body/source shape.
      notification = ::Notification.find_by(user_id: @buyer.id, source_type: "Takeaway::Order", source_id: @cart.id)
      assert notification, "the reader who left the cart open is the one told it is closed"
      assert_match(/Kansellert/i, notification.title, "the title speaks Norwegian to the reader")
    end
  end

  test "the sweep job delegates to the engine method" do
    ActsAsTenant.with_tenant(@city) do
      kitchen_with_cart
      @cart.update_columns(expires_at: cart_deadline_minutes.minutes.ago)

      TakeawayCartExpirySweepJob.perform_now

      assert_equal "cancelled", @cart.reload.status, "the job is the clock, the engine method is the hand"
    end
  end

  private

  # 45 minutes is the stated promise (CART_TTL_MINUTES); the test reaches it by
  # name so a change to the constant re-times this battery by itself.
  def cart_deadline_minutes
    Takeaway::Order::CART_TTL_MINUTES
  end

  def kitchen_with_cart
    kitchen = Takeaway::Restaurant.create!(
      user: @owner, name: "Expiry Kitchen", address: "Marken 3",
      cuisine_type: "Norwegian", city: @city, active: true,
      latitude: 60.3930, longitude: 5.3220
    )
    item = Takeaway::MenuItem.create!(restaurant: kitchen, name: "Rett", price_cents: 10_000, available: true)
    @cart = kitchen.orders.build(user: @buyer, delivery_address: "Torget 1", status: "pending")
    @cart.order_items.build(menu_item: item, quantity: 1, unit_price_cents: item.price_cents)
    @cart.save!
    @cart
  end
end
