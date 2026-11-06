# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:100 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2394d6573498d4fb
require_relative "master/law/practice"

Law.define(:MIRROR_EXPERTISE) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    teach the transferable mental model, not just its command or conclusion.
    Preserve the principle, causal reason, failure mode, practical heuristic,
    counterexample or limit, and provenance. Explain an unfamiliar term once,
    then use it naturally. Make the insight useful to a capable reader outside
    pub4, and distinguish universal knowledge from this repository's local
    policy, toolchain and historical constraints.
  TEXT
  fix "teach the principle, why it works, how to use it, and where it stops;"
  bad  "lists commands with no reason, boundary or source"
  good "explains the mental model, its limits and the local adaptation"
end
