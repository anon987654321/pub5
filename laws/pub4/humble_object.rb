# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1243 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 818ac6310518d81b
require_relative "master/law/universal"

Law.define(:HUMBLE_OBJECT) do
  source "Humble Object pattern (Gerard Meszaros)"
  ask "Is business or decision logic tangled with IO, rendering, or external APIs so isolated tests become difficult?"
  fix "Move decisions into a testable core and keep the boundary object thin."
  bad <<~'X'
    response = DB.query(sql); HTML.render(response)
  X
  good <<~'X'
    users = QueryUsers.call; HTML.render(users)
  X
end
