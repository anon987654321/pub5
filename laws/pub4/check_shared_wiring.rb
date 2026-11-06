# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml shared_wiring by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5ee129491efbf4c9
require_relative "master/lib/master"

Law.define(:CHECK_SHARED_WIRING) do
  source "pub4 MASTER/checks/checks.yml shared_wiring"
  practice "Check shared_wiring holds: Shared wiring check passed (routes, importmap, public assets, Stimulus)."
end
