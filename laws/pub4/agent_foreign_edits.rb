# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b54845f17b8676d1
require_relative "master/lib/master"

Law.define(:AGENT_FOREIGN_EDITS) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Foreign edits.** Never stage, revert, stash or rewrite edits you didn't make."
end
