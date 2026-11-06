# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml exemption_freshness by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2adcdfbe510395b0
require_relative "master/lib/master"

Law.define(:CHECK_EXEMPTION_FRESHNESS) do
  source "pub4 MASTER/checks/checks.yml exemption_freshness"
  practice "Check exemption_freshness holds: exemption_freshness: every craft-ledger exemption review is current."
end
