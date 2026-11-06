# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:565 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: dc5d8b77930aee7c
require_relative "master/law/universal"

Law.define(:NO_SHOTGUN_SURGERY) do
  source "Refactoring code smell: Shotgun Surgery (Fowler)"
  ask "Does one conceptual change require edits across many unrelated files because the missing abstraction has no single home?"
  fix "Create the missing abstraction or single source so one conceptual change has one owner."
  bad <<~'X'
    users.each { |u| audit(u) }; admins.each { |u| audit(u) }
  X
  good <<~'X'
    auditable_users.each { |u| audit(u) }
  X
end
