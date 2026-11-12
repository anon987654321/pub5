# frozen_string_literal: true

# WebRTC signaling for a paired stranger video chat. Rails carries only the
# dance - offer, answer, ICE candidates - between the two browsers of one
# encounter; the video itself flows peer-to-peer, and coturn relays the
# pairs that cannot connect directly. One channel per encounter, torn down
# the moment either peer unsubscribes: a stranger chat has no afterlife.
#
# The pairing itself is Encounter's job (waiting → matched); a subscription
# to this channel demands the matched pair on both ends and an age-verified
# account on the connecting one.
class RandomVideoChannel < ApplicationCable::Channel
  def subscribed
    encounter = find_encounter
    return reject unless encounter

    stream_from "random_video:#{encounter.id}"
    ActionCable.server.broadcast(
      "random_video:#{encounter.id}",
      { event: "peer_joined", user_id: current_user.id },
    )
  end

  def unsubscribed
    encounter = find_encounter
    return unless encounter

    ActionCable.server.broadcast(
      "random_video:#{encounter.id}",
      { event: "peer_left", user_id: current_user.id },
    )
  end

  # Relay one signalling message to the other peer. The server never reads
  # the SDP or the candidate; it addresses them.
  def relay(data)
    encounter = find_encounter
    return unless encounter

    ActionCable.server.broadcast(
      "random_video:#{encounter.id}",
      { sender: current_user.id, **(data.slice("type", "payload") || {}) },
    )
  end

  private

  # The encounter that pairs this connection's user with their matched
  # stranger. Both sides of a pairing own their own MATCHED row (pair!
  # creates one for the asker and flips the waiter's), so the user's own
  # rows suffice; the freshest is the live one.
  def find_encounter
    current_user.encounters
                .where(status: Encounter::MATCHED)
                .where(updated_at: Encounter::MATCH_REMEMBERED_FOR.ago..)
                .order(:updated_at).last
  end
end
