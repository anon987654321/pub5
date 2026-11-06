# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_HYGIENE_ALIAS_SHADOWS_LIVE_LAW by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f57371e1a57db759
require_relative "master/lib/master"

Law.define(:RATCHET_HYGIENE_ALIAS_SHADOWS_LIVE_LAW) do
  source "pub4 MASTER/data/laws.yml RATCHET_HYGIENE_ALIAS_SHADOWS_LIVE_LAW"
  practice "An alias that shadows a live law."
end
