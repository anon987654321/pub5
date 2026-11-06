# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BRINGHURST_measure by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 23c01cf2608eef6d
require_relative "master/lib/master"

Law.define(:BRINGHURST_MEASURE) do
  source "pub4 MASTER/data/laws.yml BRINGHURST_measure"
  practice "Prose measured outside 45-75 characters; 66 where one number must serve. Terminal prose wraps at 72."
end
