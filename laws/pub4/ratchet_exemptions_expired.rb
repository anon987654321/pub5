# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_EXEMPTIONS_EXPIRED by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7098f1c86a88f239
require_relative "master/lib/master"

Law.define(:RATCHET_EXEMPTIONS_EXPIRED) do
  source "pub4 MASTER/data/laws.yml RATCHET_EXEMPTIONS_EXPIRED"
  practice "Review resolutions past expiry still in force."
end
