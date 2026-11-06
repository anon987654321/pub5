# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SACRED_AUTHORSHIP by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8aa17fb993920c3d
require_relative "master/lib/master"

Law.define(:SACRED_AUTHORSHIP) do
  source "pub4 MASTER/data/laws.yml SACRED_AUTHORSHIP"
  practice "No autonomous write to a path declared sacred by the governing Soul manifest."
end
