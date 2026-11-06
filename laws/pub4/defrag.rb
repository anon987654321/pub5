# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DEFRAG by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ee33f068fa6b8fcb
require_relative "master/lib/master"

Law.define(:DEFRAG) do
  source "pub4 MASTER/data/laws.yml DEFRAG"
  practice "Bring one concept back together when it is scattered without cause."
end
