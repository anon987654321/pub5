# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml accessibility_axe by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 42ddaba086a60ce2
require_relative "master/lib/master"

Law.define(:CHECK_ACCESSIBILITY_AXE) do
  source "pub4 MASTER/checks/checks.yml accessibility_axe"
  practice "Check accessibility_axe holds: ok: axe-core finds no violation on the sampled rendered surfaces"
end
