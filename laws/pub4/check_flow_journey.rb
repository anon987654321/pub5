# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml flow_journey by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 78e74e6868c02442
require_relative "master/lib/master"

Law.define(:CHECK_FLOW_JOURNEY) do
  source "pub4 MASTER/checks/checks.yml flow_journey"
  practice "Check flow_journey holds: ok: user journeys pass with postconditions"
end
