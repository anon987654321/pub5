# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml TRUTHFUL_STATUS_false_ready by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b8d59918af645703
require_relative "master/lib/master"

Law.define(:TRUTHFUL_STATUS_FALSE_READY) do
  source "pub4 MASTER/data/laws.yml TRUTHFUL_STATUS_false_ready"
  practice "A capability reported ready when unavailable."
end
