# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Report when done by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b807fbe14d9c659c
require_relative "master/lib/master"

Law.define(:AGENT_ANYTHING_YOU_FOUND_BROKEN) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Report when done"
  practice "- Anything you found broken."
end
