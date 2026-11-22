# frozen_string_literal: true

require "test_helper"

class PairControllerTest < ActionDispatch::IntegrationTest
  def teardown
    FileUtils.rm_rf(File.join(Master::ROOT, ".master", "pairing"))
  end

  test "show reports unpaired for a visitor" do
    get "/pair"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["paired"]
  end

  test "create redeems a code and sets the cookie" do
    issued = Master::Ground::Pairing.issue(label: "test")
    post "/pair", params: { code: issued[:code] }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["ok"]
    assert_equal "messaging", body["profile"]
    assert cookies[:master_paired].present?
  end

  test "create rejects a bad code" do
    post "/pair", params: { code: "NOPE1234" }

    assert_response :unprocessable_entity
  end

  test "pair redeem works without a booted container" do
    Rails.application.config.x.master_container = nil
    issued = Master::Ground::Pairing.issue(label: "warm")
    post "/pair", params: { code: issued[:code] }

    assert_response :success
  end

  test "create notice names the clone path" do
    issued = Master::Ground::Pairing.issue(label: "clone")
    post "/pair", params: { code: issued[:code] }

    body = JSON.parse(response.body)
    assert_match(/bin\/master/, body["notice"])
  end

  test "issue and list require authentication" do
    post "/pair/issue", params: { label: "x" }
    assert_response :unauthorized

    get "/pair/list"
    assert_response :unauthorized
  end

  test "authenticated operator can issue list and revoke by subject" do
    post "/pair/issue", params: { label: "phone" }, headers: auth_headers
    assert_response :success
    issued = JSON.parse(response.body)
    assert issued["code"]

    post "/pair", params: { code: issued["code"] }
    assert_response :success
    subject = JSON.parse(response.body)["subject"]

    get "/pair/list", headers: auth_headers
    assert_response :success
    rows = JSON.parse(response.body)["rows"]
    assert rows.any? { |row| row["subject"] == subject }

    delete "/pair/#{subject}", headers: auth_headers
    assert_response :success

    get "/pair/list", headers: auth_headers
    rows = JSON.parse(response.body)["rows"]
    refute rows.any? { |row| row["subject"] == subject }
  end

  test "the admin page requires authentication" do
    get "/pair/admin"

    assert_response :unauthorized
  end

  test "the admin page lists only pairing metadata and never exposes bearer tokens" do
    issued = Master::Ground::Pairing.issue(label: "studio tablet")
    redeemed = Master::Ground::Pairing.redeem(issued[:code])

    get "/pair/admin", headers: auth_headers

    assert_response :success
    assert_includes response.body, "studio tablet"
    assert_includes response.body, redeemed[:subject]
    assert_includes response.body, "messaging access"
    assert_not_includes response.body, redeemed[:token]
  end

  test "the admin form issues a one-time code and shows it after redirect" do
    post "/pair/admin/issue", params: { label: "laptop" }, headers: auth_headers

    assert_response :see_other
    assert_redirected_to "/pair/admin"
    code = flash[:pair_code]
    assert_match(/\A[A-HJ-NP-Z2-9]{8}\z/, code)

    follow_redirect!
    assert_response :success
    assert_includes response.body, code
    assert_includes response.body, "600 seconds"
  end

  test "admin revocation removes the subject's messaging access" do
    issued = Master::Ground::Pairing.issue(label: "revoked device")
    redeemed = Master::Ground::Pairing.redeem(issued[:code])

    delete "/pair/admin/#{redeemed[:subject]}", headers: auth_headers

    assert_response :see_other
    assert_redirected_to "/pair/admin"
    refute Master::Ground::Pairing.valid_token?(redeemed[:token])
  end

  test "redeem is rate limited from the pairing budget" do
    prev = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Master::Ground::Pairing.redeem_per_minute.times do
      post "/pair", params: { code: "NOPE0000" }
      assert_response :unprocessable_entity
    end
    post "/pair", params: { code: "NOPE0000" }
    assert_response :too_many_requests
  ensure
    Rails.cache = prev
  end
end
