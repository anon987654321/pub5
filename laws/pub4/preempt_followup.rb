# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:135 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3e99cdf516e4cc83
require_relative "master/law/practice"

Law.define(:PREEMPT_FOLLOWUP) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    answer the one obvious follow-up question in the same response; no second
    round-trip.
  TEXT
  fix "answer the one obvious follow-up question in the same response;"
  bad  "answers, waits to be asked the obvious next thing"
  good "answers both in one reply"
end
