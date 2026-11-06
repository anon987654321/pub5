# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_HYGIENE_ID_CASE_COLLISIONS by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9a419f04370251a4
require_relative "master/lib/master"

Law.define(:RATCHET_HYGIENE_ID_CASE_COLLISIONS) do
  source "pub4 MASTER/data/laws.yml RATCHET_HYGIENE_ID_CASE_COLLISIONS"
  practice "Two law ids differing only in case."
end
