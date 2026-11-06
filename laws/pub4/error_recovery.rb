# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1493 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2877f14422a2e784
require_relative "master/law/universal"

Law.define(:ERROR_RECOVERY) do
  source "Nielsen Heuristic #9 - help users recover from errors"
  ask "Does an error explain what happened and what the user can do next?"
  fix "State the failed operation, relevant cause, and concrete recovery action."
  bad <<~'X'
    raise Error, "invalid"
  X
  good <<~'X'
    raise Error, "invoice 42: payment declined; update card and retry"
  X
end
