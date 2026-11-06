# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BAYMARD_CHECKOUT_COST_TRANSPARENCY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 40a67860e57a238c
require_relative "master/lib/master"

Law.define(:BAYMARD_CHECKOUT_COST_TRANSPARENCY) do
  source "pub4 MASTER/data/laws.yml BAYMARD_CHECKOUT_COST_TRANSPARENCY"
  practice "Show the current order total and explain delivery charges, fees and taxes before commitment wherever the service can calculate them. Label estimates as estimates; do not reveal avoidable charges only at the final step."
end
