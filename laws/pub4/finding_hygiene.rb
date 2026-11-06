# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml FINDING_HYGIENE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5510094666e1545b
require_relative "master/lib/master"

Law.define(:FINDING_HYGIENE) do
  source "pub4 MASTER/data/laws.yml FINDING_HYGIENE"
  practice "A finding is a hypothesis until evidence confirms it. A finding that could not measure its subject has not passed; it is inconclusive. An inconclusive finding never clears a ratchet."
end
