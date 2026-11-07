# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "uri"

class S2sPostbackJobTest < ActiveJob::TestCase
  ENV_KEYS = %w[MEDIAGO_ACCOUNT_NAME MEDIAGO_CURRENCY REVCONTENT_API_KEY].freeze

  setup do
    @saved_env = ENV.to_h.slice(*ENV_KEYS)
    @user = User.create!(
      email_address: "s2s-job-#{SecureRandom.hex(4)}@example.test",
      password: "password123"
    )
  end

  teardown do
    ENV_KEYS.each { |key| ENV.delete(key) }
    @saved_env.each { |key, value| ENV[key] = value }
  end

  def attribution!(mediago: nil, revcontent: nil)
    Shared::S2sAttribution.create!(
      user: @user,
      mediago_tracking_id: mediago,
      revcontent_rc_uuid: revcontent,
      captured_at: Time.current
    )
  end

  def conversion!(currency:, amount_cents: 1_299)
    Shared::S2sConversion.create!(
      user: @user,
      reference: SecureRandom.hex(8),
      amount_cents: amount_cents,
      currency: currency,
      converted_at: Time.current
    )
  end

  def perform_with_http(conversion)
    requests = []
    http = Object.new
    http.define_singleton_method(:request) do |request|
      requests << request
      Struct.new(:code).new("200")
    end

    Net::HTTP.stub(
      :start,
      ->(*_args, **_options, &block) { block.call(http) }
    ) do
      Shared::S2sPostbackJob.perform_now(conversion.id)
    end
    requests
  end

  def query_for(request)
    URI.decode_www_form(URI.parse("https://example.test#{request.path}").query).to_h
  end

  test "Revcontent receives whole-dollar values only for USD conversions" do
    ENV["REVCONTENT_API_KEY"] = "test-api-key"
    attribution!(revcontent: "rc_123")

    nok = conversion!(currency: "NOK")
    assert_empty perform_with_http(nok)
    assert_equal "queued", nok.reload.status
    assert_empty nok.reload.postback_results

    usd = conversion!(currency: "USD")
    requests = perform_with_http(usd)
    assert_equal 1, requests.size
    assert_equal "13", query_for(requests.first).fetch("amount")
    assert_equal "sent", usd.reload.status
  end

  test "MediaGo receives a conversion only in its configured account currency" do
    ENV["MEDIAGO_ACCOUNT_NAME"] = "brgen-test"
    ENV["MEDIAGO_CURRENCY"] = "NOK"
    attribution!(mediago: "mg_123")

    eur = conversion!(currency: "EUR")
    assert_empty perform_with_http(eur)
    assert_equal "queued", eur.reload.status

    nok = conversion!(currency: "NOK")
    requests = perform_with_http(nok)
    assert_equal 1, requests.size
    assert_equal "12.99", query_for(requests.first).fetch("conversionprice")
    assert_equal "8", query_for(requests.first).fetch("conversiontype")
    assert_equal "sent", nok.reload.status
  end

  test "payment currency uses the payable interface instead of assuming NOK" do
    Shared::S2sAttribution.capture!(user: @user, params: { "tracking_id" => "mg_456" })
    payable = Struct.new(:buyer_id, :total_cents, :payment_currency).new(@user.id, 2_500, "EUR")

    Webhooks::PaymentPaid.enqueue_s2s_conversion(payable, reference: "euro-order-1")

    conversion = Shared::S2sConversion.find_by!(user: @user, reference: "euro-order-1")
    assert_equal "EUR", conversion.currency
  end
end
