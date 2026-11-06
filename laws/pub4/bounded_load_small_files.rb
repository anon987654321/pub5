# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BOUNDED_LOAD_small_files by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 10a13f4c0c04bd1b
require_relative "master/lib/master"

Law.define(:BOUNDED_LOAD_SMALL_FILES) do
  source "pub4 MASTER/data/laws.yml BOUNDED_LOAD_small_files"
  practice "A file with more than one concept."
end
