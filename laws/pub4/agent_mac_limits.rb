# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 06257339466e87c9
require_relative "master/lib/master"

Law.define(:AGENT_MAC_LIMITS) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Mac limits.** The Mac has 8 GB: run one suite at a time, never two in parallel. Another agent is running too."
end
