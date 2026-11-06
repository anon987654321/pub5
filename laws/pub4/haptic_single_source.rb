# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:133 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ea65ca28fdcad2c2
require_relative "master/law/javascript"

Law.define(:HAPTIC_SINGLE_SOURCE) do
  path "RAILS/"
  source "Shared RAILS haptics controller - one tactile implementation"
  ask "Does Rails interaction code use the shared haptics implementation instead of reaching directly for navigator.vibrate, so suppression, timing and future native adapters remain one source of truth?"
  fix "Import the shared pub4/haptics controller or its pulse API. Keep raw navigator.vibrate behind that shared implementation."
  bad "navigator.vibrate(10)"
  good "Haptics.pulse(10)"
end
