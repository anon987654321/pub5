# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/adhoc_empty_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6b7adcc94f58f110
require_relative "master/lib/master"

Law.define(:LINT_ADHOC_EMPTY) do
  source "pub4 MASTER/tools/adhoc_empty_lint.rb"
  practice "The adhoc empty lint finds nothing above its baseline."
end
