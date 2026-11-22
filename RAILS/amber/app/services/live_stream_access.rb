# frozen_string_literal: true

# Signed, expiring access to a ticketed live stream. The token says "this
# viewer may watch this stream until this moment" and nothing else; it is
# how a Linktree visitor or a shared link carries one seat without handing
# out the session cookie. The message verifier's signature fails closed on
# any tampering; the payload's expiry fails closed after the hour.
class LiveStreamAccess
  NAMESPACE = "amber:live_stream_access"
  TOKEN_LASTS_FOR = 1.hour

  Token = Data.define(:value, :expires_at)

  class << self
    def issue(live_stream, user)
      expires_at = TOKEN_LASTS_FOR.from_now
      payload = { stream_id: live_stream.id, user_id: user.id, exp: expires_at.to_i }
      Token.new(value: verifier.generate(payload, purpose: NAMESPACE), expires_at:)
    end

    def valid?(live_stream, token_value, user)
      # The JSON serializer hands the payload back with string keys.
      payload = verifier.verified(token_value.to_s, purpose: NAMESPACE).to_h.with_indifferent_access
      return false if Time.current.to_i >= payload[:exp].to_i

      payload[:stream_id] == live_stream.id && payload[:user_id] == user&.id
    rescue StandardError
      false
    end

    private

    def verifier
      Rails.application.message_verifier(NAMESPACE)
    end
  end
end
