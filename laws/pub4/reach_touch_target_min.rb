# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REACH_touch_target_min by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9f2d480f4e44d961
require_relative "master/lib/master"

Law.define(:REACH_TOUCH_TARGET_MIN) do
  source "pub4 MASTER/data/laws.yml REACH_touch_target_min"
  practice "A target too small to hit."
end
