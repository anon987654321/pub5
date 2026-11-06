# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml META_VERSION by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 21dc263fa162742c
require_relative "master/lib/master"

Law.define(:META_VERSION) do
  source "pub4 MASTER/data/laws.yml META_VERSION"
  practice "The version of this file."
end
