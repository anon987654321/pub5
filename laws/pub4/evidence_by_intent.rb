# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:528 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5ecad32b60f29122
require_relative "master/law/universal"

Law.define(:EVIDENCE_BY_INTENT) do
  source "MASTER-native (intent-to-evidence routing)"
  ask "Does an answer depend on current, niche, uncertain, repository, browser, device, or externally verifiable facts without first selecting the evidence surface that can actually observe them?"
  fix "Route the turn by evidence need: read/search the repository for repository facts, use device capability for local hardware, use browser capability for page state, and use local knowledge or current web sources for unfamiliar or time-sensitive facts; never substitute memory for available evidence."
  bad <<~'X'
    answer = model_memory(topic)
  X
  good <<~'X'
    evidence = web_search(topic)
    answer = synthesize(evidence)
  X
end
