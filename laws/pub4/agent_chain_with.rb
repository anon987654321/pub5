# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 909d61634767c0c4
require_relative "master/lib/master"

Law.define(:AGENT_CHAIN_WITH) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Chain with &&.** Chain lint, tests and push with `&&`, so a failing step never pushes."
end
