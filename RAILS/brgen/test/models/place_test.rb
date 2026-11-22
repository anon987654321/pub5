# frozen_string_literal: true

require "test_helper"

# A place is a point on the map; one that cannot be drawn is refused at save.
class PlaceTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def place(latitude:, longitude:)
    Place.new(city: @city, name: "Bryggen", kind: "attraction", latitude:, longitude:)
  end

  test "a coordinate on the globe is accepted" do
    assert place(latitude: 60.3974, longitude: 5.3244).valid?
    assert place(latitude: -90, longitude: 180).valid?
  end

  test "public slugs are stable and unique within each city" do
    first = Place.create!(city: @city, name: "Bryggen", kind: "attraction",
                          latitude: 60.3974, longitude: 5.3244)
    second = Place.create!(city: @city, name: "Bryggen", kind: "attraction",
                           latitude: 60.3980, longitude: 5.3250)

    assert_equal "bryggen", first.slug
    assert_equal "bryggen", first.to_param
    assert_equal "bryggen-2", second.slug
    assert_equal first.id, Place.find_by!(city: @city, slug: first.to_param).id
  end

  test "external source identity is stable and unique within a city" do
    first = Place.create!(
      city: @city, name: "OpenStreetMap place", kind: "cafe",
      latitude: 60.3974, longitude: 5.3244,
      source: "openstreetmap", external_id: "node/123"
    )
    duplicate = Place.new(
      city: @city, name: "Duplicate", kind: "cafe",
      latitude: 60.3974, longitude: 5.3244,
      source: "openstreetmap", external_id: "node/123"
    )

    assert_equal "openstreetmap:node/123", first.stable_key
    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :external_id
    assert_equal "brgen:#{Place.new(id: 91).id}", Place.new(id: 91).stable_key
  end

  test "public coordinates follow the stored precision without changing canonical values" do
    point = place(latitude: 60.397456, longitude: 5.324456)
    point.location_precision = "neighbourhood"

    assert_equal [ 60.397, 5.324 ], point.public_coordinates
    assert_equal 60.397456, point.latitude.to_f
    assert_equal 5.324456, point.longitude.to_f
  end

  test "PlaceDirectory is city-scoped and excludes rejected records" do
    visible = Place.create!(city: @city, name: "Visible", kind: "cafe",
                            latitude: 60.3974, longitude: 5.3244)
    Place.create!(city: @city, name: "Rejected", kind: "cafe",
                  latitude: 60.3974, longitude: 5.3244, verification_state: "rejected")
    other_city = City.where.not(id: @city.id).first
    other_city ||= City.create!(name: "Other", domain: "other.example", slug: "other",
                                country_code: "NO", currency: "NOK", locale: "nb")
    Place.create!(city: other_city, name: "Other city", kind: "cafe",
                  latitude: 60.3974, longitude: 5.3244)

    assert_equal [ visible ], PlaceDirectory.for_city(@city).to_a
    assert_empty PlaceDirectory.for_city(nil)
    assert_equal [ visible ], PlaceDirectory.for_city(@city, kinds: [ "cafe" ]).to_a
    assert_empty PlaceDirectory.for_city(@city, verified_only: true)
  end

  test "an out-of-range latitude or longitude is refused" do
    assert_not place(latitude: 90.5, longitude: 5.32).valid?
    assert_not place(latitude: -91, longitude: 5.32).valid?
    assert_not place(latitude: 60.39, longitude: 180.1).valid?
    assert_not place(latitude: 60.39, longitude: -200).valid?
  end
end
