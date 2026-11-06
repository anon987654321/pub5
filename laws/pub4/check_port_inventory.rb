# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml port_inventory by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 75a8423375e67673
require_relative "master/lib/master"

Law.define(:CHECK_PORT_INVENTORY) do
  source "pub4 MASTER/checks/checks.yml port_inventory"
  practice "Check port_inventory holds: Port inventory check passed for apps Rails apps."
end
