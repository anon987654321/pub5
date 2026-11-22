# frozen_string_literal: true

require "base64"
require "openssl"

# TURN REST credentials: the username carries the expiry and the user, the
# password is the HMAC-SHA1 coturn itself will recompute, and a host without
# the shared secret refuses to mint one.
class TurnCredentialServiceTest < ActiveSupport::TestCase
  SECRET = "turn-rest-shared-secret"

  test "the credential matches coturn's own computation" do
    credential = TurnCredentialService.generate(user_id: 42, secret: SECRET)

    expiry = credential.username.split(":").first.to_i
    assert_operator expiry, :>, Time.current.to_i
    expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", SECRET, credential.username))
    assert_equal expected, credential.credential
    assert credential.urls.any? { |url| url.start_with?("turn:", "stun:") }
  end

  test "credentials name their user, so two users do not share one" do
    first = TurnCredentialService.generate(user_id: 1, secret: SECRET)
    second = TurnCredentialService.generate(user_id: 2, secret: SECRET)

    refute_equal first.credential, second.credential
  end

  test "a host without the shared secret raises instead of minting" do
    assert_raises(ArgumentError) do
      TurnCredentialService.generate(user_id: 1, secret: "")
    end
  end
end
