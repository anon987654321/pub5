# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0f35363e86554973
require_relative "master/lib/master"

Law.define(:AGENT_OFF_LIMITS) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Off limits.** Don't run /fix, don't touch vm23, and don't deploy."
end
