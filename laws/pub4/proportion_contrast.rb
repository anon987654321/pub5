# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml PROPORTION_contrast by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6e0ad0cfcbe333d8
require_relative "master/lib/master"

Law.define(:PROPORTION_CONTRAST) do
  source "pub4 MASTER/data/laws.yml PROPORTION_contrast"
  practice "Hierarchy that requires squinting."
end
