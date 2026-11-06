# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1281 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6635943b6d5db92a
require_relative "master/law/universal"

Law.define(:COMPOSABLE) do
  source "Unix philosophy / functional composition"
  ask "Is this operation monolithic when it could be cleanly composed from smaller independent parts?"
  fix "Expose small units with explicit inputs and outputs so they can be composed."
  bad <<~'X'
    processor.run_all(input)
  X
  good <<~'X'
    normalized = normalize(input); validated = validate(normalized)
  X
end
