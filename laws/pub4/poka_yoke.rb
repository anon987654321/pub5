# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1027 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: edced0e3bb4b819a
require_relative "master/law/universal"

Law.define(:POKA_YOKE) do
  source "Toyota Production System - poka-yoke"
  ask "Can this API be called in the wrong order, with swappable same-typed arguments, or in a meaningless state?"
  fix "Make invalid sequences or arguments difficult or impossible to express."
  bad <<~'X'
    client.send(body, token)
  X
  good <<~'X'
    client.send(token: token, body: body)
  X
end
