# frozen_string_literal: true

require "test_helper"

# The stranger video layer's doors: the room and its TURN endpoint sit behind
# the age gate (an age-verified account or an approved human verification,
# never a guest), and the TURN answer carries a minted credential only when
# the host named its shared secret.
class EncounterVideoTest < ActionDispatch::IntegrationTest
  def member(name)
    User.create!(email_address: "#{name}-#{SecureRandom.hex(4)}@example.no", password: "password123")
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "a guest is sent away by the age gate before any camera" do
    get encounter_video_path
    assert_redirected_to root_path
    assert_equal I18n.t("flash.age_verification_required"), flash[:alert]
  end

  test "a signed-in member without an age verification is sent away too" do
    sign_in(member("unverified"))

    get encounter_video_path
    assert_redirected_to root_path
    assert_equal I18n.t("flash.age_verification_required"), flash[:alert]
  end

  test "an age-verified member without a live match lands back at the wait" do
    user = member("verified")
    user.update!(age_verified_at: 1.day.ago)
    sign_in(user)

    get encounter_video_path
    assert_redirected_to waiting_encounters_path
  end

  test "an age-verified member with a live match reaches the room" do
    first = member("first")
    first.update!(age_verified_at: 1.day.ago)
    sign_in(first)
    Encounter.pair!(first)

    second = member("second")
    second.update!(age_verified_at: 1.day.ago)
    Encounter.pair!(second)

    get encounter_video_path
    assert_response :ok
  end

  test "an approved human verification also opens the gate" do
    user = member("human")
    sign_in(user)
    IdentityVerification.create!(user:, kind: "human", status: "approved")

    get encounter_turn_path
    assert_response :ok
  end

  test "the turn answer carries a minted credential when the secret exists" do
    ENV["AMBER_COTURN_SECRET"] = "test-shared-secret"
    user = member("turn")
    user.update!(age_verified_at: 1.day.ago)
    sign_in(user)

    get encounter_turn_path
    body = response.parsed_body
    assert_match(/\A\d+:\d+\z/, body.fetch("username"))
    assert body.fetch("credential").present?
    assert body.fetch("urls").any? { |url| url.start_with?("turn:", "stun:") }
  ensure
    ENV.delete("AMBER_COTURN_SECRET")
  end

  test "a host without coturn answers with no relay instead of failing" do
    ENV.delete("AMBER_COTURN_SECRET")
    user = member("nosecret")
    user.update!(age_verified_at: 1.day.ago)
    sign_in(user)

    get encounter_turn_path
    assert_response :ok
    assert_empty response.parsed_body.fetch("urls")
  end
end
