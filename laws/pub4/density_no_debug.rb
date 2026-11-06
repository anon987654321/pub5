# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_no_debug by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: cf552408a490d3ba
require_relative "master/lib/master"

Law.define(:DENSITY_NO_DEBUG) do
  source "pub4 MASTER/data/laws.yml DENSITY_no_debug"
  practice "Debug output left in."
end
