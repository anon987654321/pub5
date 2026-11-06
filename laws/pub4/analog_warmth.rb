# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1159 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a6132f77ee5bf255
require_relative "master/law/universal"

Law.define(:ANALOG_WARMTH) do
  source "MASTER-native - Dilla audio aesthetic"
  ask "Is generated audio unnaturally perfect because noise floor, saturation, timing drift, or humanized variation has been eliminated entirely?"
  fix "Introduce restrained, purposeful imperfection where the aesthetic calls for it."
  bad <<~'X'
    notes.each { |n| synth.play(n, velocity: 127, at: n.beat) }
  X
  good <<~'X'
    notes.each { |n| synth.play(n, velocity: humanize(n), at: drift(n.beat)) }
  X
end
