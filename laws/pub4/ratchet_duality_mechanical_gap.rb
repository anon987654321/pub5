# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_DUALITY_MECHANICAL_GAP by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5e4e595cab3d9226
require_relative "master/lib/master"

Law.define(:RATCHET_DUALITY_MECHANICAL_GAP) do
  source "pub4 MASTER/data/laws.yml RATCHET_DUALITY_MECHANICAL_GAP"
  practice "Laws whose mechanical detector is human."
end
