# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml FINDING_HYGIENE_inconclusive_as_pass by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fa6b901d0d217815
require_relative "master/lib/master"

Law.define(:FINDING_HYGIENE_INCONCLUSIVE_AS_PASS) do
  source "pub4 MASTER/data/laws.yml FINDING_HYGIENE_inconclusive_as_pass"
  practice "A finding recorded as pass on inconclusive evidence."
end
