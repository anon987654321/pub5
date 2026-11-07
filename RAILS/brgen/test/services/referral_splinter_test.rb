# frozen_string_literal: true

require "test_helper"

class ReferralSplinterTest < ActiveSupport::TestCase
  setup do
    @referrer = User.create!(email_address: "referrer-#{SecureRandom.hex(4)}@example.test", password: "password123")
    @invitee = User.create!(email_address: "invitee-#{SecureRandom.hex(4)}@example.test", password: "password123")
  end

  test "token is opaque and redemption grants one expiring vertical credit" do
    token = Shared::ReferralSplinter.generate!(referrer: @referrer, vertical: "playlist")
    refute_includes token, %("ref":#{@referrer.id})
    splinter = Shared::ReferralSplinter.redeem!(token:, user: @invitee)

    assert_equal @invitee, splinter.redeemed_by
    credit = Shared::ReferralCredit.find_by!(user: @referrer, vertical: "playlist")
    assert_equal "playlist_pro", credit.entitlement
    assert_in_delta 30.days.from_now.to_i, credit.expires_at.to_i, 5
    assert @referrer.reload.entitled?(:playlist_pro)
  end

  test "same token and same invitee cannot redeem twice" do
    token = Shared::ReferralSplinter.generate!(referrer: @referrer, vertical: "dating")
    Shared::ReferralSplinter.redeem!(token:, user: @invitee)
    assert_raises(ArgumentError) { Shared::ReferralSplinter.redeem!(token:, user: @invitee) }
    assert_equal 1, Shared::ReferralCredit.count
  end

  test "self referrals are rejected" do
    token = Shared::ReferralSplinter.generate!(referrer: @referrer, vertical: "playlist")
    assert_raises(ArgumentError) { Shared::ReferralSplinter.redeem!(token:, user: @referrer) }
  end

  test "tampering is rejected" do
    token = Shared::ReferralSplinter.generate!(referrer: @referrer, vertical: "playlist")
    tampered = token.sub(/.$/, token.end_with?("a") ? "b" : "a")
    assert_raises(ArgumentError) { Shared::ReferralSplinter.redeem!(token: tampered, user: @invitee) }
  end
end
