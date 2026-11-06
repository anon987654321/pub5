# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/layout_stability_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 50a951d1bda0c47f
require_relative "master/lib/master"

Law.define(:LINT_LAYOUT_STABILITY) do
  source "pub4 MASTER/tools/layout_stability_lint.rb"
  practice "The layout stability lint finds nothing above its baseline."
end
