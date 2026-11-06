# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:882 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ff61d887e5b77b68
require_relative "master/law/universal"

Law.define(:EXPLICIT_TRADEOFF) do
  source "Polished Ruby Programming - contextual trade-offs"
  ask "Where several valid implementations exist, is the chosen one presented as universally correct instead of justified by context?"
  fix "State the access pattern, failure mode, or constraint that makes the choice fit."
  bad <<~'X'
    ALWAYS_USE_ASYNC = true
  X
  good <<~'X'
    # sync: bounded local workload; async would add coordination cost
  X
end
