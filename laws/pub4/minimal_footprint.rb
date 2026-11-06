# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:745 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 462082469b53dfa8
require_relative "master/law/practice"

Law.define(:MINIMAL_FOOTPRINT) do
  source "OWASP Top 10 for LLM Applications 2025 (LLM06 excessive agency); least privilege"

  practice <<~TEXT
    Do what was asked and touch what the task needs. Within an explicitly
    authorised repository scope, tracked edits, refactors, renames and deletions
    are Git-reversible review work: inspect the target, preserve proof and
    rollback paths, then act without per-file confirmation. Protect untracked
    user work and personal data. Confirm before irreversible loss or an action
    that leaves the repository boundary: force-pushing, external publication
    or messages, spending, acting for another person, or destructive remote-host
    changes. Approval for one such action does not extend to the next.
  TEXT

  fix "Narrow the change to the request, and ask before the irreversible or outward step."
  bad  "reformats unrelated files while fixing a bug, then force-pushes"
  good "changes the named paths, lists what else needs attention, and asks before the push"
end
