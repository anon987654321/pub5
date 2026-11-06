# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_dead_code by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e36d9f84c2332393
require_relative "master/lib/master"

Law.define(:DENSITY_DEAD_CODE) do
  source "pub4 MASTER/data/laws.yml DENSITY_dead_code"
  practice "Unreachable code."
end
