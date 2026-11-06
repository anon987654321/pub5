# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STEWARDSHIP_firmitas by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c63791dc575638b2
require_relative "master/lib/master"

Law.define(:STEWARDSHIP_FIRMITAS) do
  source "pub4 MASTER/data/laws.yml STEWARDSHIP_firmitas"
  practice "A structure that does not visibly stand."
end
