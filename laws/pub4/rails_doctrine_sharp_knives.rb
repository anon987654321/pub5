# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RAILS_DOCTRINE_sharp_knives by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 511a3381e4c2b8a2
require_relative "master/lib/master"

Law.define(:RAILS_DOCTRINE_SHARP_KNIVES) do
  source "pub4 MASTER/data/laws.yml RAILS_DOCTRINE_sharp_knives"
  practice "A blunt tool where a sharp one with a clear edge would serve the expert better."
end
