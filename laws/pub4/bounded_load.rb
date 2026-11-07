# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BOUNDED_LOAD by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b3a4c141b7ac227e
require_relative "master/lib/master"

Law.define(:BOUNDED_LOAD) do
  source "pub4 MASTER/data/laws.yml BOUNDED_LOAD"
  practice "Never exceed what the reader can hold at once. Capacity is a property of people, not of the design."
  ask "Measure cognitive and operational load at the point of use: file/module size, public concepts, simultaneous state, call-chain depth, options, output volume, memory/CPU and time. Compare with explicit budgets and task complexity. A large file is not itself a failure if its interface and mental model remain bounded; cite measurements and user task evidence."
end
