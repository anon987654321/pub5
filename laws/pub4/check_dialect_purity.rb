# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml dialect_purity by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2c8c35e8eff41523
require_relative "master/lib/master"

Law.define(:CHECK_DIALECT_PURITY) do
  source "pub4 MASTER/checks/checks.yml dialect_purity"
  practice "Check dialect_purity holds: Dialect purity check passed."
end
