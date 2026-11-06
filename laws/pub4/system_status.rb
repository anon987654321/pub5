# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1453 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 87908b4dde741cc6
require_relative "master/law/universal"

Law.define(:SYSTEM_STATUS) do
  source "Nielsen Heuristic #1 - Visibility of system status"
  ask "Does a long-running operation provide enough timely feedback for the user to know what is happening?"
  fix "Show meaningful progress, current state, or the last completed checkpoint."
  bad <<~'X'
    export_all_records # runs for minutes with no output
  X
  good <<~'X'
    export_all_records { |n| progress.report(n) }
  X
end
