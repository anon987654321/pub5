# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STRUNK_WHITE_active_voice by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e03c14d0bce36dfb
require_relative "master/lib/master"

Law.define(:STRUNK_WHITE_ACTIVE_VOICE) do
  source "pub4 MASTER/data/laws.yml STRUNK_WHITE_active_voice"
  practice "The actor is not the subject of the sentence."
end
