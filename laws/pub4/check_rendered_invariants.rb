# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml rendered_invariants by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 438d6b51057582cd
require_relative "master/lib/master"

Law.define(:CHECK_RENDERED_INVARIANTS) do
  source "pub4 MASTER/checks/checks.yml rendered_invariants"
  practice "Check rendered_invariants holds: Rendered invariants passed (theme served matches theme declared; chat tab corner consistent or declared)."
end
