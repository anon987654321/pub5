# frozen_string_literal: true

require "test_helper"

# The `takeaway_delivery_area` convergence workstream: a kitchen that states a
# delivery radius has said where it will carry food, and the create-time check
# validates the reader's stored position against it — nil-safely (missing facts
# skip the check) and honestly (the refusal names the radius and the distance).
class Takeaway::DeliveryAreaTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(email_address: "area@brgen.no", password: "password123", city: @city)
    @buyer = User.strict_loading(false).create!(email_address: "faraway@brgen.no", password: "password123", city: @city)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  # Bergen degrees near the kitchen helper's pin: 0.002° lat is ~222 m.
  BERGEN = { lat: 60.3950, lng: 5.3240 }.freeze
  OSLO = { lat: 59.9139, lng: 10.7522 }.freeze

  test "an order from outside the stated radius is rejected, naming radius and distance" do
    ActsAsTenant.with_tenant(@city) do
      kitchen = kitchen_with_pin(radius_km: 3.0)
      @buyer.update!(latitude: OSLO[:lat], longitude: OSLO[:lng])

      order = order_at(kitchen, from: OSLO[:lat], lng: OSLO[:lng])

      assert_not order.save, "Oslo is outside a 3 km Bergen radius"
      errors = order.errors.details[:delivery_address]
      assert_includes errors.map { |d| d[:error] }, :outside_delivery_area
      refused = errors.find { |d| d[:error] == :outside_delivery_area }
      assert_equal 3.0, refused[:radius]
      assert_operator refused[:distance], :>, 3.0, "the refusal states the honest distance"
    end
  end

  test "an order from inside the stated radius saves" do
    ActsAsTenant.with_tenant(@city) do
      kitchen = kitchen_with_pin(radius_km: 3.0)
      @buyer.update!(latitude: BERGEN[:lat], longitude: BERGEN[:lng])

      order = order_at(kitchen, from: BERGEN[:lat], lng: BERGEN[:lng])

      assert order.save, "0.3 km is inside a 3 km radius: #{order.errors.full_messages.to_sentence}"
    end
  end

  # An unset fact is not a false one: no radius stated means the kitchen never
  # claimed an area, and refusing orders over a number nobody typed would empty
  # the vertical.
  test "a kitchen with no stated radius does not refuse a distant order" do
    ActsAsTenant.with_tenant(@city) do
      kitchen = Takeaway::Restaurant.create!(
        user: @owner, name: "No Radius Kitchen", address: "Marken 2",
        cuisine_type: "Norwegian", city: @city, active: true,
        latitude: 60.3930, longitude: 5.3220, delivery_radius_km: nil
      )
      @buyer.update!(latitude: OSLO[:lat], longitude: OSLO[:lng])

      order = order_at(kitchen, from: OSLO[:lat], lng: OSLO[:lng])

      assert order.save, "no radius stated, no area claimed"
    end
  end

  test "a radius without a kitchen pin skips the check" do
    ActsAsTenant.with_tenant(@city) do
      kitchen = kitchen_with_pin(radius_km: 3.0)
      kitchen.update_columns(latitude: nil, longitude: nil)
      @buyer.update!(latitude: OSLO[:lat], longitude: OSLO[:lng])

      order = order_at(kitchen, from: OSLO[:lat], lng: OSLO[:lng])

      assert order.save, "distance to an unpinned kitchen is unknowable"
    end
  end

  test "a radius and a pin without a stored reader position skip the check" do
    ActsAsTenant.with_tenant(@city) do
      kitchen = kitchen_with_pin(radius_km: 3.0)

      order = order_at(kitchen, from: nil, lng: nil)

      assert order.save, "the reader never stored a position to validate"
    end
  end

  # A guest order is not a model-level case: the order requires a user
  # (belongs_to, required), so the create path refuses it before any location
  # validator runs. The check under test measures a stored reader position.
  private

  def kitchen_with_pin(radius_km:)
    Takeaway::Restaurant.create!(
      user: @owner, name: "Radius Kitchen", address: "Marken 1",
      cuisine_type: "Norwegian", city: @city, active: true,
      latitude: 60.3930, longitude: 5.3220, delivery_radius_km: radius_km
    )
  end

  def order_at(kitchen, from:, lng:)
    item = kitchen.menu_items.find_by(available: true) || Takeaway::MenuItem.create!(
      restaurant: kitchen, name: "Rett", price_cents: 10_000, available: true
    )
    @buyer.update!(latitude: from, longitude: lng) if from
    order = kitchen.orders.build(user: @buyer, delivery_address: "Torget 1", status: "pending")
    order.order_items.build(menu_item: item, quantity: 1, unit_price_cents: item.price_cents)
    order
  end
end
