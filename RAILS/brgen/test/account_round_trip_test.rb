# frozen_string_literal: true

require "test_helper"
require "shared/account_round_trip"

# The GDPR sheet must re-read as the records it was written from, over brgen's
# real schema: one exported user, every owned association on the sheet,
# attribute by attribute compared by column type. Shared::AccountRoundTrip
# carries the contract; this proves brgen's classes satisfy it.
class AccountRoundTripTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.new(email_address: "rt-#{SecureRandom.hex(4)}@brgen.no", password: "password12345",
                     username: "rt_#{SecureRandom.hex(3)}", city: @city)
    @other = User.new(email_address: "rtb-#{SecureRandom.hex(4)}@brgen.no", password: "password12345",
                      username: "rtb_#{SecureRandom.hex(3)}", city: @city)
    @user.strict_loading!(false)
    @other.strict_loading!(false)
    User.transaction do
      @user.save!
      @other.save!
      @user.block!(@other)
      @user.share_drafts.create!(city: @city, title: "round-trip draft", content: "x")
    end
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the exported sheet re-reads as brgen's own records" do
    diffs = Shared::AccountRoundTrip.prove(@user)

    assert_empty diffs, diffs.join("\n")
  end
end
