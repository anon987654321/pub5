# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml typography_contract by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c7f24923e83c545a
require_relative "master/lib/master"

Law.define(:CHECK_TYPOGRAPHY_CONTRACT) do
  source "pub4 MASTER/checks/checks.yml typography_contract"
  practice "Check typography_contract holds: Typography contract passed (source declarations match the contextual reading profiles)."
end
