# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml domain_alignment by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1d21ce36b04f4d6a
require_relative "master/lib/master"

Law.define(:CHECK_DOMAIN_ALIGNMENT) do
  source "pub4 MASTER/checks/checks.yml domain_alignment"
  practice "Check domain_alignment holds: Domain alignment check passed (city domains + deploy_inventory.json/relayd checks)."
end
