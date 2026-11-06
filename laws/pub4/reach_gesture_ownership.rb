# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REACH_gesture_ownership by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b6df6e1a128c2cdb
require_relative "master/lib/master"

Law.define(:REACH_GESTURE_OWNERSHIP) do
  source "pub4 MASTER/data/laws.yml REACH_gesture_ownership"
  practice "A direct gesture that does not declare its relationship to scrolling."
end
