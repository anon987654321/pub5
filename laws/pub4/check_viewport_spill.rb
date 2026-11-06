# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml viewport_spill by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e26b5a865a898881
require_relative "master/lib/master"

Law.define(:CHECK_VIEWPORT_SPILL) do
  source "pub4 MASTER/checks/checks.yml viewport_spill"
  practice "Check viewport_spill holds: ok: nothing hangs off the right edge at 390px"
end
