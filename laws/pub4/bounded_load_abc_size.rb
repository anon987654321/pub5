# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BOUNDED_LOAD_abc_size by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 29425167693c7b56
require_relative "master/lib/master"

Law.define(:BOUNDED_LOAD_ABC_SIZE) do
  source "pub4 MASTER/data/laws.yml BOUNDED_LOAD_abc_size"
  practice "A class whose burden exceeds the reader's reach."
end
