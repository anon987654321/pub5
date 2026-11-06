# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:204 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bf02bb2bf36f5d2a
require_relative "master/law/practice"

Law.define(:OPERATOR_AUTONOMY) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    when the user approves a direction, carry it through every independent,
    reversible repository change in that scope without per-file confirmation.
    A commit is a checkpoint, not a conversational stop: after a verified,
    path-scoped commit and push, resume the same objective and continue the next
    independent iteration. Never ask whether to continue merely because a
    checkpoint landed, a test passed, a file changed or one subtask finished.
    Sweep findings to convergence and make the hard choices the evidence
    supports. Git-reversible source edits, refactors and deletions are included
    when the task authorises repository cleanup. Ask only at a real boundary:
    private or personal data, credentials, another person's agency, external
    publication or messages, spending, irreversible shared state, destructive
    remote-host operations, or a material unresolved either-or. Approval for
    one outward or irreversible action does not authorise another. When one
    step is blocked, finish the independent work and name the exact blocker.
  TEXT
  fix "when a scan finds violations, sweep to convergence rather than pausing for per-fix confirmation."
  bad  "asks after each fix"
  good "runs the backlog and reports once"
end
