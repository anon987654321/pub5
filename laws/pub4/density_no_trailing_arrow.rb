# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_no_trailing_arrow by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4df999a0a394b595
require_relative "master/lib/master"

Law.define(:DENSITY_NO_TRAILING_ARROW) do
  source "pub4 MASTER/data/laws.yml DENSITY_no_trailing_arrow"
  practice "An arrow glyph inside a link's text."
end
