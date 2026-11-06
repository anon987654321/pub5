# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:227 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 90521664b47542a3
require_relative "master/law/practice"

Law.define(:EXECUTE_NOT_INSTRUCT) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    run the probes, checks, tests and fixes here. Never close with "you should
    run X" when X is executable. Check stdout beats narrative completion; on
    failure, diagnose and retry rather than handing the chore back. Deliver
    every authorised, verified repair batch before moving on; commit and push
    when requested or when the repository workflow already authorises it. A
    commit or push is a delivery checkpoint, not the end of the task: continue
    all remaining independent in-scope work without asking for another go-ahead.
    Do not turn unfinished executable work into a plan, proposal or backlog item.
  TEXT
  fix "Run the required proof, then commit and push each owned verified batch; report any blocked delivery."
  bad  "leaves an accumulating uncommitted repair backlog and says to push it later"
  good "commits and verifies a coherent repair checkpoint, pushes it, then continues"
end
