# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml PROPORTION by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 533108a2424c9526
require_relative "master/lib/master"

Law.define(:PROPORTION) do
  source "pub4 MASTER/data/laws.yml PROPORTION"
  practice "Relationships follow a declared scale, never an arbitrary value. A number with no derivation cannot be checked or changed as a set."
  ask "Inventory declared design/engineering scales and all values that must relate to them. Check derived values, ratios, responsive breakpoints, type/space scales, density and component relationships. Recompute from source data and verify rendered values. Flag only unexplained outliers or mismatches, not intentional exceptions with documented purpose."
end
