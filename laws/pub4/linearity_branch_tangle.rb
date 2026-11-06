# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINEARITY_branch_tangle by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9bc6962560545387
require_relative "master/lib/master"

Law.define(:LINEARITY_BRANCH_TANGLE) do
  source "pub4 MASTER/data/laws.yml LINEARITY_branch_tangle"
  practice "A path that branches more than the problem requires."
end
