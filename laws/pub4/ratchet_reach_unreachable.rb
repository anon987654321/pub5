# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_REACH_UNREACHABLE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 72a7b6bbe6b75e68
require_relative "master/lib/master"

Law.define(:RATCHET_REACH_UNREACHABLE) do
  source "pub4 MASTER/data/laws.yml RATCHET_REACH_UNREACHABLE"
  practice "Laws with no enforcement surface."
end
