# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml layout_suite by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 285f502fe57b9710
require_relative "master/lib/master"

Law.define(:CHECK_LAYOUT_SUITE) do
  source "pub4 MASTER/checks/checks.yml layout_suite"
  practice "Check layout_suite holds: Layout suite passed (source laws plus complete rendered geometry, snapshots and browser diagnostics)."
end
