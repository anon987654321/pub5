# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml deploy_drift by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 11c89d490f86c8b6
require_relative "master/lib/master"

Law.define(:CHECK_DEPLOY_DRIFT) do
  source "pub4 MASTER/checks/checks.yml deploy_drift"
  practice "Check deploy_drift holds: ok: no deploy drift detected"
end
