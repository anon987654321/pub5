# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:172 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7b662b44f49ed864
require_relative "master/law/ruby"

Law.define(:MIGRATION_REMOVE_COLUMN) do
  path "/db/migrate/"
  source "Strong Migrations - safe column removal (Andrew Kane)"
  # Whether the migration documents its path is a question about the migration,
  # not about the line. amber's convert_money_to_ore does the safe thing eight
  # times — add_column, backfill with an UPDATE, then remove_column — and a
  # line-scoped detector reported all eight removals as unsafe while the
  # backfill sat three lines above each one.
  scope :file
  detect do |text|
    text.match?(/\bremove_column\b/) &&
      !text.match?(/\b(?:add_column|rename_column|update_all|execute)\b/)
  end
  fix "Document safety/backfill path before removing a column."
  bad <<~X
    def up
      remove_column :users, :legacy
    end
  X
  good <<~X
    def up
      add_column :users, :name, :string
      execute "UPDATE users SET name = legacy"
      remove_column :users, :legacy
    end
  X
end
