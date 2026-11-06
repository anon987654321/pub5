# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STEWARDSHIP by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 03f34613b7aa2ffd
require_relative "master/lib/master"

Law.define(:STEWARDSHIP) do
  source "pub4 MASTER/data/laws.yml STEWARDSHIP"
  practice "A change leaves what it touched better, and answers to what was already there. Nobody arrives at an empty site."
end
