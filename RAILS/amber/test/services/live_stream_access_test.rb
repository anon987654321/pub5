# frozen_string_literal: true

require "test_helper"

# Ticketed sessions and expiring access tokens: the host's chair is open, the
# premium plan is open, a ticket opens one seat, and a signed token admits
# exactly the viewer, the stream and the hour it was minted for.
class LiveStreamAccessTest < ActiveSupport::TestCase
  def setup
    @host = User.create!(email_address: "host-#{SecureRandom.hex(4)}@example.no", password: "password123")
    @viewer = User.create!(email_address: "viewer-#{SecureRandom.hex(4)}@example.no", password: "password123")
    @session = LiveStream.create!(user: @host, title: "KonMari live", ticketed: true, price_minor: 2900)
  end

  test "a free session is open to everyone, a ticketed one is not" do
    open = LiveStream.create!(user: @host, title: "free")
    assert open.accessible_by?(nil)
    refute @session.accessible_by?(nil)
    refute @session.accessible_by?(@viewer)
  end

  test "the host sits in the chair without a ticket" do
    assert @session.accessible_by?(@host)
  end

  test "a bought ticket admits one seat" do
    @viewer.grant_entitlement!(subject: @session, source: "live_ticket")

    assert @session.accessible_by?(@viewer)
  end

  test "an issued token admits its viewer until it expires" do
    token = LiveStreamAccess.issue(@session, @viewer)

    assert LiveStreamAccess.valid?(@session, token.value, @viewer)
  end

  test "a token is bound to one stream and one viewer" do
    token = LiveStreamAccess.issue(@session, @viewer)
    other_stream = LiveStream.create!(user: @host, title: "other", ticketed: true)
    stranger = User.create!(email_address: "s-#{SecureRandom.hex(4)}@example.no", password: "password123")

    refute LiveStreamAccess.valid?(other_stream, token.value, @viewer)
    refute LiveStreamAccess.valid?(@session, token.value, stranger)
  end

  test "an expired token answers no and a forged one answers no" do
    expired = { stream_id: @session.id, user_id: @viewer.id, exp: 1.minute.ago.to_i }
    forged = { stream_id: @session.id, user_id: @viewer.id, exp: 1.hour.from_now.to_i }

    signed = Rails.application.message_verifier("other:namespace").generate(expired)
    refute LiveStreamAccess.valid?(@session, signed, @viewer)
    refute LiveStreamAccess.valid?(@session, JSON.generate(forged), @viewer)
  end
end
