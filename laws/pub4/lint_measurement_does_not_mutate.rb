# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINT_MEASUREMENT_DOES_NOT_MUTATE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 73e1f621a47e632e
require_relative "master/lib/master"

Law.define(:LINT_MEASUREMENT_DOES_NOT_MUTATE) do
  source "pub4 MASTER/data/laws.yml LINT_MEASUREMENT_DOES_NOT_MUTATE"
  practice "calibration measurement_only forbids resolution automatic on the same law."
end
