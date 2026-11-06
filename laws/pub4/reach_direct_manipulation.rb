# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REACH_direct_manipulation by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 26104e3f523cbb8f
require_relative "master/lib/master"

Law.define(:REACH_DIRECT_MANIPULATION) do
  source "pub4 MASTER/data/laws.yml REACH_direct_manipulation"
  practice "A gesture that moves a proxy instead of the thing under the input."
end
