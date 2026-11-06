# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1099 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d8a371f4435a620e
require_relative "master/law/universal"

Law.define(:SELF_EXPLAINING) do
  source "Clean Code - self-documenting code"
  ask "Does this name clearly reveal intent without requiring a comment to decode it?"
  fix "Rename around the domain action, value, or invariant."
  bad <<~'X'
    def do_it(x)
  X
  good <<~'X'
    def refresh_access_token(token)
  X
end
