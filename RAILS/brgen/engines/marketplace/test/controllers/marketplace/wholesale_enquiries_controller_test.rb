# frozen_string_literal: true

require "test_helper"

class Marketplace::WholesaleEnquiriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    host! "markedsplass.brgen.no"
    @owner = User.create!(email_address: "wh_owner@example.com", password: "secret1234")
    @buyer = User.create!(email_address: "wh_buyer@example.com", password: "secret1234")
    @stranger = User.create!(email_address: "wh_stranger@example.com", password: "secret1234")
    @store = Marketplace::Store.create!(owner: @owner, name: "Mandarinen", vertical: "wholesale")
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "secret1234" }
  end

  def enquiry_attributes
    {
      buyer_company_name: "Bergen Innkjøp AS",
      organisation_number: "912 345 678",
      contact_name: "Kari Buyer",
      contact_email: "kari@example.com",
      contact_phone: "+47 900 00 000",
      requested_items: "Asian rice, 10 bags; cooking oil, 4 cartons",
      delivery_location: "Bergen, 5008",
      wanted_at: 2.weeks.from_now.to_date
    }
  end

  test "a signed-out visitor must sign in before requesting wholesale terms" do
    get marketplace.new_shop_wholesale_enquiry_path(@store)

    assert_redirected_to new_session_path
  end

  test "a business customer can send an enquiry without creating a consumer order" do
    sign_in(@buyer)

    assert_difference -> { Marketplace::WholesaleEnquiry.count }, 1 do
      assert_no_difference -> { Marketplace::Order.count } do
        post marketplace.shop_wholesale_enquiries_path(@store),
             params: { wholesale_enquiry: enquiry_attributes }
      end
    end

    enquiry = Marketplace::WholesaleEnquiry.order(:id).last
    assert_redirected_to marketplace.shop_wholesale_enquiry_path(@store, enquiry)
    assert_equal "912345678", enquiry.organisation_number
    assert_equal "submitted", enquiry.status
  end

  test "the store owner can reply and the buyer can read the supplier response" do
    enquiry = Marketplace::WholesaleEnquiry.create!(
      store: @store, buyer: @buyer, **enquiry_attributes
    )
    sign_in(@owner)

    get marketplace.shop_wholesale_enquiries_path(@store)
    assert_response :success
    assert_includes response.body, "Bergen Innkjøp AS"

    patch marketplace.shop_wholesale_enquiry_path(@store, enquiry),
          params: { wholesale_enquiry: { seller_response: "Please confirm the quantities; pricing follows." } }
    assert_redirected_to marketplace.shop_wholesale_enquiry_path(@store, enquiry)
    assert_equal "responded", enquiry.reload.status
    assert_equal "Please confirm the quantities; pricing follows.", enquiry.seller_response

    delete main_app.session_path
    sign_in(@buyer)
    get marketplace.shop_wholesale_enquiry_path(@store, enquiry)
    assert_response :success
    assert_includes response.body, "pricing follows"
  end

  test "another customer cannot read or reply to an enquiry" do
    enquiry = Marketplace::WholesaleEnquiry.create!(
      store: @store, buyer: @buyer, **enquiry_attributes
    )
    sign_in(@stranger)

    get marketplace.shop_wholesale_enquiry_path(@store, enquiry)
    assert_response :forbidden

    patch marketplace.shop_wholesale_enquiry_path(@store, enquiry),
          params: { wholesale_enquiry: { seller_response: "Not authorised" } }
    assert_response :forbidden
    assert_equal "submitted", enquiry.reload.status
  end

  test "a buyer cannot open the enquiry inbox" do
    sign_in(@buyer)

    get marketplace.shop_wholesale_enquiries_path(@store)

    assert_response :forbidden
  end

  test "the wholesale workflow cannot be opened for an ordinary shop" do
    @store.update!(vertical: "sports")
    sign_in(@buyer)

    get marketplace.new_shop_wholesale_enquiry_path(@store)

    assert_response :not_found
  end
end
