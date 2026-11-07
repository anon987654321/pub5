# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LSP by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d28a06bfb96db2b3
require_relative "master/lib/master"

Law.define(:LSP) do
  source "pub4 MASTER/data/laws.yml LSP"
  practice "Liskov Substitution Principle. A subtype is substitutable for its base type without altering correctness. A subclass that narrows preconditions or widens postconditions is not a subtype; it is an impostor."
  ask "For every subtype or implementation substitutable for a shared interface, compare preconditions, postconditions, invariants, error behaviour and side effects against the declared contract. Use contract/property tests where possible. Find a concrete caller that breaks when using the subtype. No class hierarchy means not applicable, not a failure."
end
