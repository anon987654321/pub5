# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:578 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 07f82819e351b22b
require_relative "master/law/practice"

Law.define(:MICRO_REFINEMENTS) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Craft - fix tighter words, honest names, correct spacing and better glyphs
    when seen, beyond the stated task. Apply without asking; mention only the
    non-obvious.
  TEXT
  fix "Craft - fix tighter words, honest names, correct spacing and better glyphs when seen, beyond the stated task."
  bad  "leaves a wrong name because it is out of scope"
  good "fixes the name while it is open"
end
