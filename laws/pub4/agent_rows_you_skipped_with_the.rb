# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Report when done by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 675233d013dfb580
require_relative "master/lib/master"

Law.define(:AGENT_ROWS_YOU_SKIPPED_WITH_THE) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Report when done"
  practice "- Rows you skipped, with the reason."
end
