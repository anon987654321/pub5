# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml OCP by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d84417e52ffd2a49
require_relative "master/lib/master"

Law.define(:OCP) do
  source "pub4 MASTER/data/laws.yml OCP"
  practice "Open/Closed Principle. A unit is open for extension and closed for modification. A new requirement changes behaviour by adding a variant, not by editing a decision the unit already made."
  ask "Identify a stable policy decision and the variation points that are expected by current requirements. Inspect recent change history, callers and tests to determine whether a new variant repeatedly edits the same decision. Prefer an explicit extension seam only where there is at least one real second variant. Fail on demonstrated repeated edits or unsafe branching; do not demand speculative plugin architecture."
end
