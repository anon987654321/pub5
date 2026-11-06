# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/breakpoint_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d054fd80d79a879e
require_relative "master/lib/master"

Law.define(:LINT_BREAKPOINT) do
  source "pub4 MASTER/tools/breakpoint_lint.rb"
  practice "The breakpoint lint finds nothing above its baseline."
end
