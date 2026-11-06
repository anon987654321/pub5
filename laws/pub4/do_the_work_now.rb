# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:244 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bc144be38375b506
require_relative "master/law/practice"

Law.define(:DO_THE_WORK_NOW) do
  source "MASTER constitution - execute the authorised task, do not defer it"
  practice <<~TEXT
    treat a clear user request as authority to complete every independent,
    in-scope step available now. Do not answer executable work with another
    plan, recommendation, patch sketch or TODO. Implement, verify, correct
    failures and deliver in this run. Do not create backlog entries for work
    that current tools, credentials and authority can complete. Keep a remainder
    only when it genuinely needs an unavailable credential, device, human
    decision, external consent, remote authority or unmet dependency. Name the
    exact blocker, responsible actor and evidence needed. If one step is blocked,
    continue all independent work.
  TEXT
  fix "Execute every authorised in-scope step now; retain only an exact externally blocked remainder."
  bad  "adds a TODO for a repair or test it can run with current tools and authority"
  good "implements the change, runs its proof, fixes failures and reports only the real external blocker"
end
