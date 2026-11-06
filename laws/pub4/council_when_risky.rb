# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:291 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: be7d223eb4c78a57
require_relative "master/law/practice"

Law.define(:COUNCIL_WHEN_RISKY) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    council is Review-stage deliberation with a Security veto. Run it on
    dangerous patterns, material multi-file diffs, or when config enables it;
    scan plus sweep is the default loop. Record whether the trigger applied,
    whether review ran and completed, its outcome, and whether Security actually
    exercised its veto. Distinguish a review that was not required from one
    not run, unavailable, incomplete or blocked. A declared panel, requested
    review, missing response or skipped Security pass is never a successful
    review.
  TEXT
  fix "council is Review-stage deliberation with a Security veto."
  bad  "council on every turn"
  good "council on a multi-file diff"
end
