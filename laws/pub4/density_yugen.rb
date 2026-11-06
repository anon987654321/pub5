# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_yugen by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5a62fd5d569a2f26
require_relative "master/lib/master"

Law.define(:DENSITY_YUGEN) do
  source "pub4 MASTER/data/laws.yml DENSITY_yugen"
  practice "The work states everything and implies nothing."
end
