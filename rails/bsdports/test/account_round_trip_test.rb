# frozen_string_literal: true

require "test_helper"
require "shared/account_round_trip"

# The GDPR sheet must re-read as the records it was written from, over
# bsdports' real schema: one exported user, its sessions on the sheet,
# attribute by attribute compared by column type. Shared::AccountRoundTrip
# carries the contract; this proves bsdports' classes satisfy it.
class AccountRoundTripTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "rt-#{SecureRandom.hex(4)}@example.com", password: "correct horse battery")
    @user.strict_loading!(false)
    Session.create!(user: @user)
  end

  test "the exported sheet re-reads as bsdports' own records" do
    diffs = Shared::AccountRoundTrip.prove(@user)

    assert_empty diffs, diffs.join("\n")
  end
end
