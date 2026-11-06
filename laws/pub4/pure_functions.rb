# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1403 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6778ef10a0718f65
require_relative "master/law/universal"

Law.define(:PURE_FUNCTIONS) do
  source "Functional programming - referential transparency"
  ask "Does this function depend on hidden mutable state or ambient inputs that callers cannot see?"
  fix "Pass dependencies explicitly and keep deterministic logic pure."
  bad <<~'X'
    def total(items); items.sum + Time.now.to_i; end
  X
  good <<~'X'
    def total(items, tax_rate:); items.sum * tax_rate; end
  X
end
