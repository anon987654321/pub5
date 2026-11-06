# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Before you start by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f5b8310b6c57c620
require_relative "master/lib/master"

Law.define(:AGENT_NEVER_EDIT_MASTER_DATA_SOUL) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Before you start"
  practice "- Never edit MASTER/data/soul.yml or MASTER/data/laws.yml."
end
