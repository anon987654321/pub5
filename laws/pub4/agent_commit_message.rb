# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fc6055f7d8b970dd
require_relative "master/lib/master"

Law.define(:AGENT_COMMIT_MESSAGE) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Commit message.**\n  - Subject: capitalised, at most 72 chars, no type prefix, no full stop.\n  - Then a blank line and a body saying what changed, why, and how it was proven.\n  - End with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.\n  - Add `LINT_SKIP: <law> <reason>` lines only for pre-existing findings."
end
