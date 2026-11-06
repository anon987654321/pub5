# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:152 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 207d2f5a9d899d3b
require_relative "master/law/ruby"

Law.define(:MIGRATION_ADD_REFERENCE_NO_FK) do
  path "/db/migrate/"
  source "Rails migrations - foreign_key: true (Strong Migrations)"
  # A polymorphic reference names no single table, so it cannot carry a
  # foreign key; asking for one is asking for a migration that will not run.
  detect { |line| line.match?(/add_reference(?!.*(?:foreign_key:|polymorphic:\s*true))/) }
  fix "Add `foreign_key: true` to enforce referential integrity."
  bad  "add_reference :posts, :user"
  good "add_reference :posts, :user, foreign_key: true\nadd_reference :reactions, :reactable, polymorphic: true\n"
end
