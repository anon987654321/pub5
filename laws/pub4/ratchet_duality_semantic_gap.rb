# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_DUALITY_SEMANTIC_GAP by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 11fa5354a33a1276
require_relative "master/lib/master"

Law.define(:RATCHET_DUALITY_SEMANTIC_GAP) do
  source "pub4 MASTER/data/laws.yml RATCHET_DUALITY_SEMANTIC_GAP"
  practice "Laws whose semantic test is human."
end
