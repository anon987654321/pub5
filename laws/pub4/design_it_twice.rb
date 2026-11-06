# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:858 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e216cc61e309f479
require_relative "master/law/universal"

Law.define(:DESIGN_IT_TWICE) do
  source "A Philosophy of Software Design - Design it Twice"
  ask "Was a consequential design committed without considering at least one materially different approach?"
  fix "Sketch and compare alternatives before committing."
  bad <<~'X'
    solution = first_design
  X
  good <<~'X'
    options = [design_a, design_b]; solution = choose(options)
  X
end
