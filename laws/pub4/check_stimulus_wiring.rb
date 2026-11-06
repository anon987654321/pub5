# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml stimulus_wiring by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: cf2d9e5391110308
require_relative "master/lib/master"

Law.define(:CHECK_STIMULUS_WIRING) do
  source "pub4 MASTER/checks/checks.yml stimulus_wiring"
  practice "Check stimulus_wiring holds: Stimulus wiring check passed."
end
