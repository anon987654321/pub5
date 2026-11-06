# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/typography_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5fbcc7897f980d1c
require_relative "master/lib/master"

Law.define(:LINT_TYPOGRAPHY) do
  source "pub4 MASTER/tools/typography_lint.rb"
  practice "The typography lint finds nothing above its baseline."
end
