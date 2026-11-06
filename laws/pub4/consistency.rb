# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1555 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5a288599cf27dc37
require_relative "master/law/universal"

Law.define(:CONSISTENCY) do
  source "Nielsen Heuristic #4 - consistency and standards"
  ask "Are the same concepts, actions, or states named or presented differently in different places?"
  fix "Choose one vocabulary and interaction pattern and reuse it."
  bad <<~'X'
    button "Remove"; link "Delete"
  X
  good <<~'X'
    button "Delete"; link "Delete"
  X
end
