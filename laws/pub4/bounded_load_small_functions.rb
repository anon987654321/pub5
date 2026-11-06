# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BOUNDED_LOAD_small_functions by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 15cee4bf2e3935c7
require_relative "master/lib/master"

Law.define(:BOUNDED_LOAD_SMALL_FUNCTIONS) do
  source "pub4 MASTER/data/laws.yml BOUNDED_LOAD_small_functions"
  practice "A method requiring a notebook."
end
