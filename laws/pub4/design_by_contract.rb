# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1615 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5ab157c02d10ac2b
require_relative "master/law/universal"

Law.define(:DESIGN_BY_CONTRACT) do
  source "Design by Contract (Bertrand Meyer)"
  ask "Are important preconditions, postconditions, and invariants left implicit at an interface?"
  fix "State and enforce the contract at the boundary."
  bad <<~'X'
    def divide(a, b); a / b; end
  X
  good <<~'X'
    def divide(a, b); raise ArgumentError if b.zero?; a / b; end
  X
end
