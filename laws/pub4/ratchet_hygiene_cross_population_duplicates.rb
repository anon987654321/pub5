# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_HYGIENE_CROSS_POPULATION_DUPLICATES by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 77b4cb3c897b170e
require_relative "master/lib/master"

Law.define(:RATCHET_HYGIENE_CROSS_POPULATION_DUPLICATES) do
  source "pub4 MASTER/data/laws.yml RATCHET_HYGIENE_CROSS_POPULATION_DUPLICATES"
  practice "The same law stated in two places."
end
