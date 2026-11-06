# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_identical_branches by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b31fd17c799e19a4
require_relative "master/lib/master"

Law.define(:DENSITY_IDENTICAL_BRANCHES) do
  source "pub4 MASTER/data/laws.yml DENSITY_identical_branches"
  practice "Two identical conditional branches."
end
