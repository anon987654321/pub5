# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SPLIT by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fb26a3e43d9461a2
require_relative "master/lib/master"

Law.define(:SPLIT) do
  source "pub4 MASTER/data/laws.yml SPLIT"
  practice "Separate unlike concerns before consolidating equivalent units."
end
