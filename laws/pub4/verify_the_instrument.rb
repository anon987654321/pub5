# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:159 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2453cc9ab14797c7
require_relative "master/law/practice"

Law.define(:VERIFY_THE_INSTRUMENT) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    a clean result is a claim about the measurement, not about the code.
    Before acting on "no callers", "no findings", "0 unread", re-run without
    the filter that produced it and confirm the check can still see a
    known-positive case. Every self-inflicted break on 2026-08-10 came from a
    check that was measuring nothing and said so as a pass - a grep whose
    `grep -v` hid the three callers it was clearing, a source scan that
    matched the comment explaining a rule rather than the rule, and two
    baselines still granting exemptions to a deleted file.
  TEXT
  fix "a clean result is a claim about the measurement, not about the code."
  bad  "acts on a clean result"
  good "re-runs without the filter that produced it"
end
