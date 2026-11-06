# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REACH_reduced_motion by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 901bc7262d258aeb
require_relative "master/lib/master"

Law.define(:REACH_REDUCED_MOTION) do
  source "pub4 MASTER/data/laws.yml REACH_reduced_motion"
  practice "An animation with no reduced-motion equivalent."
end
