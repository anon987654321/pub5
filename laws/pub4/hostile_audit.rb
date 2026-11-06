# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:697 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 240b1d415db758c9
require_relative "master/law/practice"

Law.define(:HOSTILE_AUDIT) do
  source "MASTER constitution: self-audit"
  practice <<~TEXT
    Interrogate applicable Laws, assumptions and evidence against the proposed
    change. Try to falsify the leading explanation with a plausible
    counter-hypothesis; distinguish observed facts, attributed claims, inference
    and unknowns. For material decisions, ask what evidence would change the
    conclusion. Use data/council.yml#questions.biases and #questions.red_team
    when the risk and review path call for them rather than maintaining a second
    bias checklist. Consider relevant user, maintainer, security and failure-mode
    perspectives in proportion to risk. Keep the smallest robust remediation
    supported by evidence. Never manufacture agreement, persona quotas or filler;
    council remains conditional under COUNCIL_WHEN_RISKY.
  TEXT
  fix "Try to falsify the change against the law before accepting it."
  bad  "accepts the change after a single friendly reading"
  good "tries to break the change and records what survived"
end
