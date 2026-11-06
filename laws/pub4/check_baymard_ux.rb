# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml baymard_ux by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9a2915cb257e9976
require_relative "master/lib/master"

Law.define(:CHECK_BAYMARD_UX) do
  source "pub4 MASTER/checks/checks.yml baymard_ux"
  practice "Check baymard_ux holds: baymard UX source checks measured; participant evidence reported separately"
end
