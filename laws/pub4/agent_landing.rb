# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9b4bffece368fb3d
require_relative "master/lib/master"

Law.define(:AGENT_LANDING) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Landing.** Don't commit, push, rebase, stash or pull directly. Land changes only through the queue:\n  - `ruby $S/push_queue.rb add MSGFILE \"row-id;;row-id\" $S/<export>/PATH=PATH ...`\n    - The first argument is a message FILE path.\n    - The second lists the refinement rows to flip to done; use \"\" for none.\n    - `SOURCE=PATH` commits SOURCE's bytes as PATH, and a missing SOURCE deletes PATH.\n  - Then push under the lock: `ruby -e 'File.open(ARGV[0],\"w\"){|f| f.flock(File::LOCK_EX); exec(\"ruby\", ARGV[1], \"push\")}' $S/push.lock $S/push_queue.rb`.\n  - On FOREIGN CHANGE, rebuild from the new origin and retry.\n  - Read $S/push_queue.rb first."
end
