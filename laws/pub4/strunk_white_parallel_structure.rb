# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STRUNK_WHITE_parallel_structure by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e81dc5972b01093d
require_relative "master/lib/master"

Law.define(:STRUNK_WHITE_PARALLEL_STRUCTURE) do
  source "pub4 MASTER/data/laws.yml STRUNK_WHITE_parallel_structure"
  practice "Coordinated elements that do not share grammatical form."
end
