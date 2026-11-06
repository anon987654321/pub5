# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1541 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4f414c4534f882b3
require_relative "master/law/universal"

Law.define(:HELP_AND_DOCUMENTATION) do
  source "Nielsen Heuristic #10 - help and documentation"
  ask "When the user gets stuck, is concrete, searchable, task-focused help available near the action?"
  fix "Provide focused guidance where the question arises, with an actionable next step."
  bad <<~'X'
    button "Deploy" # no explanation or error guidance
  X
  good <<~'X'
    button "Deploy"; help "Build and release the current revision"
  X
end
