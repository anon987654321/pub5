# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:613 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 91cfc5f9a4b65e17
require_relative "master/law/universal"

Law.define(:TRANSFORMATIONS) do
  source "Transformation Priority Premise (Robert C. Martin)"
  ask "Is the design modeling work as scattered mutable state when it can be expressed as a clear sequence of transformations?"
  practice "On a structural or prose cleanup, inventory and classify first; defragment, decouple, flatten, merge, split, relocate, rename, reorder, remove, reflow and simplify in that order, then prove preservation."
  fix "Express the flow as input-to-output transformations with explicit stages."
  bad <<~'X'
    state[:x] = normalize(state[:x]); state[:x] = validate(state[:x])
  X
  good <<~'X'
    validated = validate(normalize(input))
  X
end
