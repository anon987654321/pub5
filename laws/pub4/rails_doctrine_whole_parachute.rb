# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RAILS_DOCTRINE_whole_parachute by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 49d649f7447e8b58
require_relative "master/lib/master"

Law.define(:RAILS_DOCTRINE_WHOLE_PARACHUTE) do
  source "pub4 MASTER/data/laws.yml RAILS_DOCTRINE_whole_parachute"
  practice "A layer adopted partially, so the reader must hold both the framework's shape and the shape it was meant to replace."
end
