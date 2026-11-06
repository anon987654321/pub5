# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml accessibility_tree by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3b0feef81469e60f
require_relative "master/lib/master"

Law.define(:CHECK_ACCESSIBILITY_TREE) do
  source "pub4 MASTER/checks/checks.yml accessibility_tree"
  practice "Check accessibility_tree holds: ok: rendered accessibility tree exposes names for interactive controls and informative images"
end
