# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:786 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 83399b255dcab617
require_relative "master/law/universal"

Law.define(:PULL_COMPLEXITY_DOWN) do
  source "A Philosophy of Software Design - complexity belongs behind the interface"
  ask "Is complexity being pushed onto callers instead of absorbed by the implementation?"
  fix "Move complexity behind a small, stable interface."
  bad <<~'X'
    client.retry && client.timeout && client.auth && client.parse(response)
  X
  good <<~'X'
    client.fetch(request)
  X
end
