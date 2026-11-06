# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1579 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3ef7804bc512dd01
require_relative "master/law/universal"

Law.define(:CACHE_LLM) do
  source "MASTER-native - cache repeat LLM work"
  ask "Is the same expensive LLM request repeated when the input and relevant context are unchanged?"
  fix "Cache deterministic or safely repeatable requests with an explicit invalidation boundary."
  bad <<~'X'
    3.times { llm.complete(prompt) }
  X
  good <<~'X'
    response = cache.fetch(prompt_key) { llm.complete(prompt) }
  X
end
