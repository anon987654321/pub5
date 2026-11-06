# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1481 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f3340ab3376c2a78
require_relative "master/law/universal"

Law.define(:USER_CONTROL) do
  source "Nielsen Heuristic #3 - User control and freedom"
  ask "Can the user cancel or undo a consequential operation when doing so is technically feasible?"
  fix "Provide an explicit cancel, undo, or rollback path."
  bad <<~'X'
    publish! # irreversible and no cancel path
  X
  good <<~'X'
    publish_with_undo_window
  X
end
