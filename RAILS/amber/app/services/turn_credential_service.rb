# frozen_string_literal: true

require "base64"
require "openssl"

# Time-limited coturn TURN credentials, per the TURN REST API: the app and
# the turnserver share one static secret (AMBER_COTURN_SECRET); the app
# mints a username of "<unix_expiry>:<user>" and the HMAC-SHA1 of it as the
# password, and coturn recomputes the same HMAC to admit the peer. No
# persistent TURN password exists anywhere, and a credential dies with its
# timestamp.
class TurnCredentialService
  TTL = 1.hour.to_i

  Credential = Data.define(:username, :credential, :ttl, :urls) do
    def to_h = { username:, credential:, ttl:, urls: }
  end

  class << self
    def generate(user_id:, secret: ENV["AMBER_COTURN_SECRET"], ttl: TTL)
      raise ArgumentError, "AMBER_COTURN_SECRET is not set" if secret.to_s.strip.empty?

      expiry = Time.current.to_i + ttl.to_i
      username = "#{expiry}:#{user_id}"
      Credential.new(
        username:,
        credential: Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", secret, username)),
        ttl: ttl.to_i,
        urls: urls,
      )
    end

    private

    # coturn owns the transport ports; this list names the public entrances.
    # The host's own domain carries the TLS turn, the env may add regions.
    def urls
      [ ENV["AMBER_TURN_URL"].presence || "turn:amberapp.art:3478?transport=udp",
       ENV["AMBER_TURN_TCP_URL"].presence || "turn:amberapp.art:3478?transport=tcp",
       "stun:amberapp.art:3478" ].compact
    end
  end
end
