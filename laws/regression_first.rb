# frozen_string_literal: true

# The boot's absence reached the operator before it reached any gate. The
# order that repairs it is now the rule, so the next regression is triaged
# before it is argued about: the reference tree's bytes are the spec, and
# memory - "I ported it faithfully", "the rebuilt version is equivalent" -
# is not evidence.
Law.define(:REGRESSION_FIRST) do
  source "PLAN.md section 19; the operator's catch of the dropped boot (2026-11-07)"
  practice "- **Regression first.** An operator-caught regression outranks all new work: triage it in the " \
           "same session, restore the tuned behaviour from the reference tree - pub4's bytes are the spec, " \
           "memory is not - re-render the surface as evidence, and only then resume new work. A rebuilt, " \
           "simplified or modernised variant of a tuned surface is not a restore; only the recorded " \
           "decision that owns the change makes it one."
end
