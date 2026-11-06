# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/css_coverage_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 74a73b25e1ff1ed5
require_relative "master/lib/master"

Law.define(:LINT_CSS_COVERAGE) do
  source "pub4 MASTER/tools/css_coverage_lint.rb"
  practice "because a raised baseline without a list is a number nobody can act on."
end
