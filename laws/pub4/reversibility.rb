# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:846 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9b9d7354a32f11bc
require_relative "master/law/universal"

Law.define(:REVERSIBILITY) do
  source "The Pragmatic Programmer - reversibility"
  ask "Is a hard-to-reverse decision being made when a reversible option provides the same present value?"
  fix "Prefer rollback paths, replaceable boundaries, and staged changes."
  bad <<~'X'
    DROP TABLE users
  X
  good <<~'X'
    rename_table :users, :users_archive
  X
end
