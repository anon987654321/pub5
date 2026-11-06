# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml META_SCHEMA by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9c4e36fef87a75e3
require_relative "master/lib/master"

Law.define(:META_SCHEMA) do
  source "pub4 MASTER/data/laws.yml META_SCHEMA"
  practice "The schema version of this file."
end
