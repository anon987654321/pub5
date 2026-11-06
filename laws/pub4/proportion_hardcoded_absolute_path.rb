# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml PROPORTION_hardcoded_absolute_path by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4c2067d1e66cd2d7
require_relative "master/lib/master"

Law.define(:PROPORTION_HARDCODED_ABSOLUTE_PATH) do
  source "pub4 MASTER/data/laws.yml PROPORTION_hardcoded_absolute_path"
  practice "A machine-specific path in code."
end
