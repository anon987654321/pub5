# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:176 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: dd3192dc96d16556
require_relative "master/law/practice"

Law.define(:A_FINDING_IS_A_HYPOTHESIS) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    a recorded finding states where and what, and is routinely wrong about
    both. Re-measure before fixing. Of 129 hardcoded_copy findings, 38 were
    already translated one branch away, 8 named the first of two occurrences
    in their file, and 1 was hardcoded Norwegian a literal-matching rule
    cannot tell from English. Fixing a stale finding list edits code that was
    already right.
  TEXT
  fix "a recorded finding states where and what, and is routinely wrong about both."
  bad  "fixes every line the list names"
  good "re-measures, then fixes what is still there"
end
