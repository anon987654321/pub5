# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1836 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0baa755be5caa205
require_relative "master/law/universal"

Law.define(:ABSTRACTION) do
  source "laws.yml ABSTRACTION - appropriate boundaries and information hiding"
  ask "Does this artifact expose implementation detail, hide a load-bearing contract, or introduce an abstraction whose indirection exceeds the problem it solves? Assess the boundary in code, prose, behavior and presentation; return CLEAN when the boundary makes the concept easier to use and verify."
  practice "Hide volatile mechanics behind a small truthful contract; do not hide important behavior behind ceremony."
  fix "Expose the needed contract, encapsulate the unstable detail, or delete the abstraction if direct expression is clearer."
  bad "Callers depend on undocumented internals or traverse an abstraction that adds no useful policy."
  good "The public surface is small, intent-revealing and sufficient to exercise the behavior."
end
