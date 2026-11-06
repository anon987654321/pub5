# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:541 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d4cde517ab4043c1
require_relative "master/law/practice"

Law.define(:STYLE) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    KISS - the shortest correct form in every language. No filler, redundant
    branches, ceremonial patterns, defensive over-engineering, or comments
    restating code.
  TEXT
  fix "KISS - the shortest correct form in every language."
  bad  "a defensive branch that cannot be reached"
  good "the shortest correct form"
end
