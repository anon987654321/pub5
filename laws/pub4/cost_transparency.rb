# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1567 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e0be5a73dac9a6c9
require_relative "master/law/universal"

Law.define(:COST_TRANSPARENCY) do
  source "MASTER-native - surface LLM token cost"
  ask "Are LLM calls made without exposing enough token or cost information to the operator when that information is available?"
  fix "Surface measured input, output, and cost data at the appropriate operator boundary."
  bad <<~'X'
    llm.complete(prompt)
  X
  good <<~'X'
    llm.complete(prompt) # reports usage tokens=1240 cost=$0.0021
  X
end
