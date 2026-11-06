# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml PROXIMITY_anti_divitis by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3352b02cb107d454
require_relative "master/lib/master"

Law.define(:PROXIMITY_ANTI_DIVITIS) do
  source "pub4 MASTER/data/laws.yml PROXIMITY_anti_divitis"
  practice "A div that only wraps a div."
end
