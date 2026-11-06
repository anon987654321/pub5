# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3b23fa1b9cda74b3
require_relative "master/lib/master"

Law.define(:AGENT_THE_OPERATOR_S_DECISIONS) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **The operator's decisions.** The operator granted full approval to make product and pricing calls.\n  - Make the conservative, reversible choice.\n  - State each decision in the commit body.\n  - Never invent facts: no made-up allergen data, prices or legal text. Where real data is needed, build the mechanism and leave the data empty, with a clear owner-facing note."
end
