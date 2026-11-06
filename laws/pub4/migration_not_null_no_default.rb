# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:551 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7d1214dc47d412ed
require_relative "master/law/ruby"

Law.define(:MIGRATION_NOT_NULL_NO_DEFAULT) do
  path "/db/migrate/"
  source "Kleppmann, DDIA - schema evolution under rolling deploy"
  detect do |line|
    line.match?(/\badd_column\b/) && line.match?(/null:\s*false/) && !line.match?(/default:\s/)
  end
  fix "Give the column a default:, or backfill in one migration and constrain in the next."
  bad  "add_column :posts, :kind, :string, null: false"
  good "add_column :posts, :kind, :string, null: false, default: \"post\""
end
