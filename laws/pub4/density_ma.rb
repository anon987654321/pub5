# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_ma by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c50a70fa8ac19e63
require_relative "master/lib/master"

Law.define(:DENSITY_MA) do
  source "pub4 MASTER/data/laws.yml DENSITY_ma"
  practice "Negative space treated as a gap rather than a measure."
end
