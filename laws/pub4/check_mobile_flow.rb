# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml mobile_flow by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 57ac09cbea84c06e
require_relative "master/lib/master"

Law.define(:CHECK_MOBILE_FLOW) do
  source "pub4 MASTER/checks/checks.yml mobile_flow"
  practice "Check mobile_flow holds: ok: mobile journey floor holds"
end
