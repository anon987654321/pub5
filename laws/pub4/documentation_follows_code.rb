# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:276 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: cbbbb5df095a3529
require_relative "master/law/practice"

Law.define(:DOCUMENTATION_FOLLOWS_CODE) do
  source "MASTER constitution - one source of truth and executable documentation"
  ask "After a code change, are affected user documentation, interface contracts, configuration instructions and operations guidance reconciled, and have generated documents been regenerated from their canonical source?"
  practice <<~TEXT
    after every code change, reconcile the affected documentation in the same
    repair batch. When behavior, public interfaces, commands, configuration or
    operations change, update the relevant README/contract/runbook and regenerate
    every affected generated document through its canonical generator. Never
    hand-edit generated copies, and do not churn unrelated documents.
  TEXT
  fix "Update affected documentation and regenerate generated copies from the canonical source before closing the batch."
  bad  "changes a command or interface but leaves its documented contract stale"
  good "updates the affected README/contract and runs the canonical docs generator"
end
