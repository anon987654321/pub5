# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SIMPLIFY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0b2f49cc32cfd1be
require_relative "master/lib/master"

Law.define(:SIMPLIFY) do
  source "pub4 MASTER/data/laws.yml SIMPLIFY"
  practice "Pull out incidental complexity after structural changes."
end
