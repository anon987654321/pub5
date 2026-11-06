# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml layout_snapshot by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9e985a774d8d8bc6
require_relative "master/lib/master"

Law.define(:CHECK_LAYOUT_SNAPSHOT) do
  source "pub4 MASTER/checks/checks.yml layout_snapshot"
  practice "Check layout_snapshot holds: ok: layout snapshots match committed baselines"
end
