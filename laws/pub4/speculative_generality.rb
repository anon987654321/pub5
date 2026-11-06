# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1427 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6869f1f13a6af6cc
require_relative "master/law/universal"

Law.define(:SPECULATIVE_GENERALITY) do
  source "Refactoring - Speculative Generality; YAGNI"
  ask "Is code generalized for a future requirement that has no present evidence or consumer?"
  fix "Remove speculative hooks and add abstraction when a real use case arrives."
  bad <<~'X'
    supports_five_future_formats = true
  X
  good <<~'X'
    format = :json
  X
end
