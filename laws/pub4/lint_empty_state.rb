# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/empty_state_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c4458155b571ad09
require_relative "master/lib/master"

Law.define(:LINT_EMPTY_STATE) do
  source "pub4 MASTER/tools/empty_state_lint.rb"
  practice "The empty state lint finds nothing above its baseline."
end
