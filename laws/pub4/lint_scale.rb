# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/scale_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a4c4d2a54406f7cc
require_relative "master/lib/master"

Law.define(:LINT_SCALE) do
  source "pub4 MASTER/tools/scale_lint.rb"
  practice "The scale lint finds nothing above its baseline."
end
