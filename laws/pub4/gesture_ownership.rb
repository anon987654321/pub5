# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:242 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: cfe59bdcfc847e50
require_relative "master/law/css"

Law.define(:GESTURE_OWNERSHIP) do
  path "RAILS/"
  source "Pointer Events and touch-action - gesture ownership"
  ask "Does a drag or swipe surface explicitly declare which pan remains with the browser and which axis belongs to the interaction? A direct-manipulation gesture must not compete silently with page scrolling, navigation gestures, or pull-to-refresh."
  fix "Declare touch-action on the gesture surface: use pan-y for horizontal swipes in a vertical page, pan-x for vertical rails, or none when the interaction deliberately owns both axes. Keep an equivalent keyboard/control path."
  bad ".card-stack { touch-action: auto; }"
  good ".card-stack { touch-action: pan-y; }"
end
