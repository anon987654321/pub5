# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:506 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: cf4024e0a2b0ead5
require_relative "master/law/practice"

Law.define(:INVERTED_PYRAMID) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Inverted Pyramid (prose) - commits, comments, and log lines lead with the
    fact; context trails.
  TEXT
  fix "Inverted Pyramid (prose) - commits, comments, and log lines lead with the fact;"
  bad  "context, then the fact"
  good "the fact, then context"
end
