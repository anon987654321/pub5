# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:115 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2c6139639f11c544
require_relative "master/law/javascript"

Law.define(:TACTILE_FEEDBACK) do
  path "RAILS/"
  source "Haptic interaction feedback - optional secondary signal"
  ask "When haptic feedback is used, is it attached to a meaningful user action or threshold, fired at the start of direct manipulation when appropriate, gracefully unavailable, power-conscious, and never the only confirmation?"
  fix "Keep haptics short and optional, trigger them only for meaningful interactions, suppress them when the page is hidden or the device is power-constrained, and preserve a visible or semantic equivalent."
  bad "navigator.vibrate([100,100,100,100,100]) for every hover or pointermove"
  good "pointerdown -> brief tick; commit -> success pattern; unsupported or suppressed -> visible feedback remains"
end
