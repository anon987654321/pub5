# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1806 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d36fb3a39b4db6e3
require_relative "master/law/universal"

Law.define(:LINEARITY) do
  source "laws.yml LINEARITY - sequential flow with minimal branches; cyclomatic complexity, McCabe 1976"
  ask "Does this change make the path through the code harder to follow in order, with deeper nesting, extra branches, or control flow that jumps back and forth instead of running top to bottom?"
  practice "Read the code once, top to bottom, and arrive at the result."
  fix "Flatten with guard clauses, extract the branch that breaks the sequence, and order steps as they run."
  bad "Nest three conditionals inside a loop so the success path sits at the deepest indent."
  good "Return early on each failure, then run the success path unindented to the end."
end
