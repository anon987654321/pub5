# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Read the manual first (operator, 2026-11-06) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8d07b782ef465c35
require_relative "master/lib/master"

Law.define(:AGENT_BEFORE_EDITING_OPENBSD_READ_MAN) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Read the manual first (operator, 2026-11-06)"
  practice "- Before editing OPENBSD/: read man for every tool, daemon or config file you touch (on vm23 or man.openbsd.org)."
end
