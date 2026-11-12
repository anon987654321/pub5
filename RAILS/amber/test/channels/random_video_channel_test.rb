# frozen_string_literal: true

require "test_helper"

# The stranger video signaling layer: a matched pair subscribes and streams
# from one room, the relay addresses messages, and a subscription without a
# live match is rejected.
class RandomVideoChannelTest < ActionCable::Channel::TestCase
  def setup
    @first = User.create!(email_address: "v1-#{SecureRandom.hex(4)}@example.no", password: "password123")
    @second = User.create!(email_address: "v2-#{SecureRandom.hex(4)}@example.no", password: "password123")
    Encounter.pair!(@first)
    Encounter.pair!(@second)
    @encounter = @first.encounters.matched.order(:updated_at).last
  end

  test "a matched pair streams one room" do
    stub_connection(current_user: @first)
    subscribe

    assert subscription.confirmed?
    assert_has_stream "random_video:#{@encounter.id}"
  end

  test "a subscription without a live match is rejected" do
    third = User.create!(email_address: "v3-#{SecureRandom.hex(4)}@example.no", password: "password123")
    stub_connection(current_user: third)
    subscribe

    assert subscription.rejected?
  end

  test "the relay addresses the message without reading it" do
    stub_connection(current_user: @first)
    subscribe

    assert_broadcast_on("random_video:#{@encounter.id}",
                        sender: @first.id, "type" => "offer", "payload" => { "sdp" => "x" }) do
      perform :relay, { "type" => "offer", "payload" => { "sdp" => "x" } }
    end
  end

  test "a leaver's peer hears the teardown" do
    stub_connection(current_user: @first)
    subscribe

    assert_broadcast_on("random_video:#{@encounter.id}", event: "peer_left", user_id: @first.id) do
      unsubscribe
    end
  end
end
