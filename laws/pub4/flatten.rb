# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml FLATTEN by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: dae9afba45cd6aad
require_relative "master/lib/master"

Law.define(:FLATTEN) do
  source "pub4 MASTER/data/laws.yml FLATTEN"
  practice "Remove needless wrappers, delegation layers, and empty directories."
end
