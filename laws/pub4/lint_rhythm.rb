# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/rhythm_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 92464c92a1ffa3b7
require_relative "master/lib/master"

Law.define(:LINT_RHYTHM) do
  source "pub4 MASTER/tools/rhythm_lint.rb"
  practice "The rhythm lint finds nothing above its baseline."
end
