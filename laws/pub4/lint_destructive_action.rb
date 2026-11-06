# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/rails/operator/destructive_action_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b5d8605011937f95
require_relative "master/lib/master"

Law.define(:LINT_DESTRUCTIVE_ACTION) do
  source "pub4 MASTER/tools/rails/operator/destructive_action_lint.rb"
  practice "The destructive action lint finds nothing above its baseline."
end
