# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:115 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 157bece67dfcedc4
require_relative "master/law/practice"

Law.define(:SURFACE_ERRORS_FIRST) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    failures and blockers lead the response; context and explanation follow.
  TEXT
  fix "failures and blockers lead the response;"
  bad  "context first, failure in the last line"
  good "the failure first, context after"
end
