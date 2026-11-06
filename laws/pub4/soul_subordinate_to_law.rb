# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SOUL_SUBORDINATE_TO_LAW by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3275e469196c3c1d
require_relative "master/lib/master"

Law.define(:SOUL_SUBORDINATE_TO_LAW) do
  source "pub4 MASTER/data/laws.yml SOUL_SUBORDINATE_TO_LAW"
  practice "Soul owns system identity, preservation principles and source authority; laws.yml alone owns individual Law identities and requirement statements. The Soul manifest must not create or redefine those Law records."
end
