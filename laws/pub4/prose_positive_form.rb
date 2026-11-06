# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1689 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5e47251ceecaa246
require_relative "master/law/universal"

Law.define(:PROSE_POSITIVE_FORM) do
  source "Strunk, Elements of Style - put statements in positive form"
  ask "Is a statement phrased as a negation when a direct positive verb or construction says the same thing more clearly?"
  fix "Prefer the direct positive form when it preserves meaning."
  bad <<~'X'
    He did not remember the password.
  X
  good <<~'X'
    He forgot the password.
  X
end
