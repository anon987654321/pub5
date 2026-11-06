# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_aesthetic_integrity by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1d42f3bc37224979
require_relative "master/lib/master"

Law.define(:DENSITY_AESTHETIC_INTEGRITY) do
  source "pub4 MASTER/data/laws.yml DENSITY_aesthetic_integrity"
  practice "Appearance does not match function."
end
