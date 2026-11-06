# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1505 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3dae7644527e5adb
require_relative "master/law/universal"

Law.define(:MATCH_REAL_WORLD) do
  source "Nielsen Heuristic #2 - match between system and real world"
  ask "Does the interface expose implementation jargon where a familiar real-world term would be clearer?"
  fix "Use the user's domain vocabulary for labels, actions, and concepts."
  bad <<~'X'
    button "invoke_job_executor"
  X
  good <<~'X'
    button "Run job"
  X
end
