# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:495 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5cb78f98752d89af
require_relative "master/law/practice"

Law.define(:CINEMA_PALETTE) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Motion Design - shadow/midtone/highlight triplets; cubic-bezier easing on
    every transition.
  TEXT
  fix "Motion Design - shadow/midtone/highlight triplets;"
  bad  "one flat hue"
  good "shadow, midtone and highlight"
end
