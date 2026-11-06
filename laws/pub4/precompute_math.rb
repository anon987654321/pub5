# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1123 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 50694e113b465b42
require_relative "master/law/universal"

Law.define(:PRECOMPUTE_MATH) do
  source "MASTER-native - precompute constant math"
  ask "Are invariant trig, noise, or lookup calculations repeated per frame or per object?"
  fix "Precompute invariant values once and reuse them."
  bad <<~'X'
    objects.each { |o| angle = Math.sin(Math::PI / 4) * o.scale }
  X
  good <<~'X'
    sin_quarter = Math.sin(Math::PI / 4); objects.each { |o| angle = sin_quarter * o.scale }
  X
end
