# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Report when done by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: eb0d76700142d134
require_relative "master/lib/master"

Law.define(:AGENT_EACH_LANDED_COMMIT_ITS_ORIGIN) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Report when done"
  practice "- Each landed commit: its origin hash, subject and rows. Verify each hash with `git merge-base --is-ancestor <hash> origin/main`."
end
