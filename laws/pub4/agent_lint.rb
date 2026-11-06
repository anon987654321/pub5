# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0f72ba7c0343a3a3
require_relative "master/lib/master"

Law.define(:AGENT_LINT) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Lint.** Lint changed lines before queuing:\n  - `MASTER/bin/operator lint --changed-lines` diffs against the stale local HEAD.\n  - `$S/lint_ob.rb` lints against origin.\n  - Fix every finding you caused."
end
