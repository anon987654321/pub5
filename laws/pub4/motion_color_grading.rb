# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:603 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: eaa9b8a8d76a29b8
require_relative "master/law/practice"

Law.define(:MOTION_COLOR_GRADING) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Motion Design - ease all motion with frame-independent delta time;
    ease-out arrivals, ease-in-out crossfades, never a linear snap. Palettes
    anchor on complements with shadow/midtone/highlight triplets.
  TEXT
  fix "Motion Design - ease all motion with frame-independent delta time;"
  bad  "a linear snap"
  good "ease-out on arrival, frame-independent"
end
