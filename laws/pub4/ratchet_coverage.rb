# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:603 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1c0a342cb75d88aa
require_relative "master/lib/master"

Law.define(:RATCHET_COVERAGE) do
  source "pub4 MASTER/lib/operator/ratchets.rb:603"
  practice "coverage_ratchet keeps per-app floors; these are FLOORS, so the direction is up and \"slack\" means the tree improved without the floor being raised."
end
