# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RAILS_DOCTRINE_integrated_systems by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1097cb0d3664bf14
require_relative "master/lib/master"

Law.define(:RAILS_DOCTRINE_INTEGRATED_SYSTEMS) do
  source "pub4 MASTER/data/laws.yml RAILS_DOCTRINE_integrated_systems"
  practice "A system split into parts that must be developed, deployed, and reasoned about separately without a measured reason."
end
