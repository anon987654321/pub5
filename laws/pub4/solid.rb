# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SOLID by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 04252abc1b803968
require_relative "master/lib/master"

Law.define(:SOLID) do
  source "pub4 MASTER/data/laws.yml SOLID"
  practice "Five object-oriented design principles. Each exists because a class designed without it becomes brittle under the next change."
  ask "Evaluate the five principles separately, only where object boundaries exist: responsibility cohesion, extension without editing stable decisions, substitutability under contracts, client-specific interfaces, and dependency direction. For each concern, cite concrete class/module/contract and a counterexample. Do not fail merely because a class has multiple methods or because a principle can be named; demonstrate the change coupling or behavioural break."
end
