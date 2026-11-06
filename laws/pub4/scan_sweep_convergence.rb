# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:262 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8c8a450b34632411
require_relative "master/law/practice"

Law.define(:SCAN_SWEEP_CONVERGENCE) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    "through" means deep scan the path and attempt every actionable finding,
    then rescan and repeat until DONE or an explicit truthful terminal state.
    No fixer, time limit, quota pause or failed pass proves everything was
    repaired. Name every unresolved finding, exclusion, unmeasured surface and
    human decision. Lint written paths and audit lib/ for drift after mutations.
  TEXT
  fix "Sweep every actionable finding and prove convergence; report every blocker and unresolved item."
  bad  "one scan, then stops or reports success with unresolved findings"
  good "repairs and rechecks every actionable finding, or names the precise non-DONE terminal state"
end
