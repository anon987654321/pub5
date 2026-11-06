# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:462 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d5d3c0a01b6d38bf
require_relative "master/law/practice"

Law.define(:NO_CONSECUTIVE_BLANK_LINES) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Boy Scout Rule - one blank line between sections; zero between related
    lines.
  TEXT
  fix "Boy Scout Rule - one blank line between sections;"
  bad  "three blank lines between methods"
  good "one"
end
