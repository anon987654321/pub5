# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RELOCATE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 485ee09adf34999d
require_relative "master/lib/master"

Law.define(:RELOCATE) do
  source "pub4 MASTER/data/laws.yml RELOCATE"
  practice "Put a thing beside the concept that owns it."
end
