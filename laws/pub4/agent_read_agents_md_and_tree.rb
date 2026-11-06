# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Before you start by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0b12ed051717cde4
require_relative "master/lib/master"

Law.define(:AGENT_READ_AGENTS_MD_AND_TREE) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Before you start"
  practice "- Read AGENTS.md and TREE_CONTRACTS.md, and run `ruby MASTER/tools/agent_context.rb --json`."
end
