# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1737 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 92055d5b14729426
require_relative "master/law/universal"

Law.define(:GRICE_COOPERATIVE) do
  source "Grice - cooperative principle (quantity, quality, relation, manner)"
  ask "Does this communication say too much or too little, assert what is unverified, drift off-topic, or obscure the point through needless complexity?"
  fix "Provide the needed information, qualify uncertain claims, stay relevant, and make the path clear."
  bad <<~'X'
    The system is definitely perfect and, by the way, here are unrelated implementation details.
  X
  good <<~'X'
    The test passed locally; CI has not run yet.
  X
end
