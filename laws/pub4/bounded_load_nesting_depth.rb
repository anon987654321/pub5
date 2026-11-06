# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BOUNDED_LOAD_nesting_depth by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 56fd28541f1680d8
require_relative "master/lib/master"

Law.define(:BOUNDED_LOAD_NESTING_DEPTH) do
  source "pub4 MASTER/data/laws.yml BOUNDED_LOAD_nesting_depth"
  practice "Nesting deeper than the reader can follow."
end
