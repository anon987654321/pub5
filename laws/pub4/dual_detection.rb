# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:541 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bce94dbc0ad0eb0f
require_relative "master/law/universal"

Law.define(:DUAL_DETECTION) do
  source "MASTER-native (lexical + semantic detection)"
  ask "Does verification rely only on regex or only on an LLM when the subject can be checked with both deterministic and semantic evidence?"
  fix "Layer deterministic detection with semantic review where both add independent evidence."
  bad <<~'X'
    rule = /danger/
  X
  good <<~'X'
    rule = lexical_check + semantic_check
  X
end
