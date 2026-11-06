# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:184 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d94889d3d48d9e1d
require_relative "master/law/css"

Law.define(:SCOPED_CSS) do
  source "CSS @scope - Baseline 2026"
  ask "Can a component's styles leak across unrelated DOM regions because its selectors are broader than its ownership boundary?"
  fix "Prefer component-local selectors or @scope where it removes selector leakage without adding unnecessary abstraction."
  bad ".card h2 { ... }"
  good "@scope (.card) { h2 { ... } }"
end
