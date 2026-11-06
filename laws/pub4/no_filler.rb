# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:716 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e9f9f66fc0f4b3de
require_relative "master/law/practice"

Law.define(:NO_FILLER) do
  source "MASTER constitution: communication conduct"
  practice <<~TEXT
    Lead with the action, result, blocker, or evidence. Do not spend response
    space narrating that work is about to happen or merely acknowledging the
    request.
  TEXT
  fix "Lead with the result or action."
  bad  "Got it. Sure. I will now begin the work."
  good "The failing reader is MASTER/data/laws.yml."
end
