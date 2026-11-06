# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml PROXIMITY_file_sprawl by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2c63818b76a39f7a
require_relative "master/lib/master"

Law.define(:PROXIMITY_FILE_SPRAWL) do
  source "pub4 MASTER/data/laws.yml PROXIMITY_file_sprawl"
  practice "One concept scattered across files that change together."
end
