# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1779 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4712285031f78f93
require_relative "master/law/universal"

Law.define(:RATCHET_INTEGRITY) do
  source "MASTER ratchet policy"
  ask "Does a ratchet or threshold change preserve its meaning, or was the threshold moved merely to absorb new debt or make the current tree pass?"
  practice "A ratchet may make progress harder to lose, never easier to redefine."
  fix "Keep the existing threshold or justify a measured structural improvement before changing it."
  bad "Increase the allowed violation count because the scan found more violations."
  good "Remove violations first, then tighten or preserve the threshold against the improved baseline."
end
