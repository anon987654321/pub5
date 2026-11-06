# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:383 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9dacc372740026b6
require_relative "master/law/universal"

Law.define(:FUNCTIONAL_CORE) do
  source "Functional Core, Imperative Shell (Gary Bernhardt)"
  ask "Are IO, database, network, filesystem, or process side effects scattered deep inside business logic instead of isolated at the edges?"
  fix "Return values from the core and move IO to the shell."
  bad <<~'X'
    def calculate_total(items); DB.save(calculate_total(items)); end
  X
  good <<~'X'
    total = calculate_total(items); DB.save(total)
  X
end
