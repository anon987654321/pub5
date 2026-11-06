# frozen_string_literal: true

require "test_helper"
require "shared/account_round_trip"

# The GDPR sheet must re-read as the records it was written from, over
# amber's real schema: one exported user, its privacy settings and profile on
# the sheet, attribute by attribute compared by column type.
# Shared::AccountRoundTrip carries the contract; this proves amber's classes
# satisfy it.
class AccountRoundTripTest < ActiveSupport::TestCase
  # ensure_identity_records auto-creates the user's privacy_setting,
  # profile and creator_profile - the real records the sheet must carry.
  setup do
    @user = User.create!(email_address: "rt-#{SecureRandom.hex(4)}@example.no", password: "password123")
    @user.strict_loading!(false)
  end

  test "the exported sheet re-reads as amber's own records" do
    diffs = Shared::AccountRoundTrip.prove(@user)

    assert_empty diffs, diffs.join("\n")
  end
end
