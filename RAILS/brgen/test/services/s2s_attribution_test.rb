# frozen_string_literal: true

require "test_helper"

class S2sAttributionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "s2s-#{SecureRandom.hex(4)}@example.test", password: "password123")
  end

  test "captures supported click ids without storing raw session or IP data" do
    Shared::S2sAttribution.capture!(user: @user, params: {
      "trackingid" => "mg_123", "rc_uuid" => "rc_456"
    })
    row = Shared::S2sAttribution.find_by!(user: @user)
    assert_equal "mg_123", row.mediago_tracking_id
    assert_equal "rc_456", row.revcontent_rc_uuid
    refute row.attributes.key?("session_id")
    refute row.attributes.key?("ip_address")
  end

  test "ignores malformed and anonymous identifiers" do
    Shared::S2sAttribution.capture!(user: @user, params: { "trackingid" => "bad\nvalue" })
    assert_equal 0, Shared::S2sAttribution.count
    guest = User.create!(email_address: "guest-s2s-#{SecureRandom.hex(4)}@example.test",
                         password: "password123", guest: true)
    Shared::S2sAttribution.capture!(user: guest, params: { "trackingid" => "mg_123" })
    assert_equal 0, Shared::S2sAttribution.count
  end

  test "conversion creation is idempotent for the same paid reference" do
    Shared::S2sAttribution.capture!(user: @user, params: { "trackingid" => "mg_123" })
    first = Shared::S2sAttribution.enqueue_conversion(user_id: @user.id, reference: "payment_1", amount_cents: 2900)
    second = Shared::S2sAttribution.enqueue_conversion(user_id: @user.id, reference: "payment_1", amount_cents: 2900)
    assert_equal first.id, second.id
    assert_equal 1, Shared::S2sConversion.count
  end
end
