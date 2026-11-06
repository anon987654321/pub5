# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINEARITY_navigation_dead_end by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1163a94720fe2d77
require_relative "master/lib/master"

Law.define(:LINEARITY_NAVIGATION_DEAD_END) do
  source "pub4 MASTER/data/laws.yml LINEARITY_navigation_dead_end"
  practice "A flow that returns the reader to no clear next state."
end
