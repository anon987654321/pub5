# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:601 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e58802ae77ff0fe3
require_relative "master/law/universal"

Law.define(:ORTHOGONALITY) do
  source "The Pragmatic Programmer - orthogonality"
  ask "Does changing one dimension force unrelated changes in another, such as database details leaking into UI or style changing structure?"
  fix "Decouple dimensions so changes remain local."
  bad <<~'X'
    view = User.where(active: true).to_a.map { |u| "<b>#{u.name}</b>" }
  X
  good <<~'X'
    users = User.active; render_users(users)
  X
end
