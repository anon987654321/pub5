# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:566 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: dfc56786059b2ac1
require_relative "master/law/practice"

Law.define(:LINT_BEAUTIFY) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Boy Scout Rule - touching a file obliges a full-file lint pass, not only
    the edited lines. Collapse double blanks, fix spacing, and reassess every
    comment: delete what-comments, keep a one-line why only when non-obvious.
  TEXT
  fix "Boy Scout Rule - touching a file obliges a full-file lint pass, not only the edited lines."
  bad  "lints only the edited lines"
  good "lints the whole file it touched"
end
