# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:163 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c4ead7488f4b7986
require_relative "master/law/ruby"

Law.define(:MIGRATION_FIND_OR_CREATE_BY) do
  path "/db/migrate/"
  source "Rails best practice - find_or_create_by races"
  detect { |line| line.match?(/find_or_create_by/) }
  fix "Back find_or_create_by with a unique index to prevent duplicates."
  bad  "Role.find_or_create_by(name: 'admin')"
  good "Role.create!(name: 'admin')"
end
