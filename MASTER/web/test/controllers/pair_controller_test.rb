# frozen_string_literal: true

require "test_helper"

class PairControllerTest < ActionDispatch::IntegrationTest
  def teardown
    FileUtils.rm_rf(Rails.root.join("tmp", "public_runtime", ".master", "pairing"))
  end

  test "show reports unpaired for a visitor" do
    get "/pair"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["paired"]
  end

  test "create redeems a code and sets the cookie" do
    issued = Master::Ground::Pairing.issue(label: "test", root: Rails.root.join("tmp", "public_runtime").to_s)
    post "/pair", params: { code: issued[:code] }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["ok"]
    assert_equal "public", body["profile"]
    assert cookies[:master_paired].present?
  end

  test "create rejects a bad code" do
    post "/pair", params: { code: "NOPE1234" }

    assert_response :unprocessable_entity
  end

  test "pair redeem works without a booted container" do
    Rails.application.config.x.master_container = nil
    issued = Master::Ground::Pairing.issue(label: "warm", root: Rails.root.join("tmp", "public_runtime").to_s)
    post "/pair", params: { code: issued[:code] }

    assert_response :success
  end

  test "create notice names the clone path" do
    issued = Master::Ground::Pairing.issue(label: "clone", root: Rails.root.join("tmp", "public_runtime").to_s)
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
    issued = Master::Ground::Pairing.issue(label: "studio tablet", root: Rails.root.join("tmp", "public_runtime").to_s)
    redeemed = Master::Ground::Pairing.redeem(issued[:code], root: Rails.root.join("tmp", "public_runtime").to_s)

    get "/pair/admin", headers: auth_headers

    assert_response :success
    assert_includes response.body, "studio tablet"
    assert_includes response.body, redeemed[:subject]
    assert_includes response.body, "browser conversation only"
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

  test "admin revocation removes the browser pairing" do
    issued = Master::Ground::Pairing.issue(label: "revoked device", root: Rails.root.join("tmp", "public_runtime").to_s)
    redeemed = Master::Ground::Pairing.redeem(issued[:code], root: Rails.root.join("tmp", "public_runtime").to_s)

    delete "/pair/admin/#{redeemed[:subject]}", headers: auth_headers

    assert_response :see_other
    assert_redirected_to "/pair/admin"
    refute Master::Ground::Pairing.valid_token?(redeemed[:token], root: Rails.root.join("tmp", "public_runtime").to_s)
  end

  test "admin audit shows issue pair and revoke without codes or bearer tokens" do
    issued = Master::Ground::Pairing.issue(label: "audit tablet", actor: "web_operator", root: Rails.root.join("tmp", "public_runtime").to_s)
    paired = Master::Ground::Pairing.redeem(issued[:code], root: Rails.root.join("tmp", "public_runtime").to_s)
    delete "/pair/admin/#{paired[:subject]}", headers: auth_headers
    assert_response :see_other

    get "/pair/admin", headers: auth_headers
    assert_response :success
    assert_includes response.body, "One-time code issued"
    assert_includes response.body, "Device paired"
    assert_includes response.body, "Device access revoked"
    assert_includes response.body, "browser conversation only"
    refute_includes response.body, issued[:code]
    refute_includes response.body, paired[:token]
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
  test "web pairing cannot mint or redeem local messaging credentials" do
    web_root = Rails.root.join("tmp", "public_runtime").to_s
    Dir.mktmpdir do |local_root|
      local = Master::Ground::Pairing.issue(root: local_root, label: "local")
      post "/pair", params: { code: local[:code] }
      assert_response :unprocessable_entity

      web = Master::Ground::Pairing.issue(root: web_root, label: "browser")
      post "/pair", params: { code: web[:code] }
      assert_response :success
      refute Master::Ground::Pairing.valid_token?(cookies[:master_paired], root: local_root)
      assert Master::Ground::Pairing.redeem(local[:code], root: local_root)
    end
  end
end
