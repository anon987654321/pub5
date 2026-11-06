# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_EXEMPTIONS_WITHOUT_EXPIRY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ed5ce0176f95111c
require_relative "master/lib/master"

Law.define(:RATCHET_EXEMPTIONS_WITHOUT_EXPIRY) do
  source "pub4 MASTER/data/laws.yml RATCHET_EXEMPTIONS_WITHOUT_EXPIRY"
  practice "Review resolutions accepted with no expiry."
end
