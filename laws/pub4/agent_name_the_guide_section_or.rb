# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Read the manual first (operator, 2026-11-06) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7a0046201c5a78e9
require_relative "master/lib/master"

Law.define(:AGENT_NAME_THE_GUIDE_SECTION_OR) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Read the manual first (operator, 2026-11-06)"
  practice "- Name the guide section or man page in the commit body."
end
