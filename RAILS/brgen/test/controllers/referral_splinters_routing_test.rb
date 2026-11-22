# frozen_string_literal: true

require "test_helper"

class ReferralSplintersRoutingTest < ActionDispatch::IntegrationTest
  TOKEN = "splinter_iv.tag.ciphertext"

  test "creates referral splinters from the collection route" do
    assert_routing(
      { method: "post", path: "/referral_splinters" },
      { controller: "referral_splinters", action: "create" }
    )
  end

  test "shows the complete opaque token rather than treating its dots as a format" do
    assert_routing(
      { method: "get", path: "/referral_splinters/#{TOKEN}" },
      { controller: "referral_splinters", action: "show", token: TOKEN }
    )
  end

  test "redeems the complete opaque token" do
    assert_routing(
      { method: "post", path: "/referral_splinters/#{TOKEN}/redeem" },
      { controller: "referral_splinters", action: "redeem", token: TOKEN }
    )
  end
end
