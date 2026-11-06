# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml META_DIALECT by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9c3121672c3719c3
require_relative "master/lib/master"

Law.define(:META_DIALECT) do
  source "pub4 MASTER/data/laws.yml META_DIALECT"
  practice "The dialect of the operator's secondary language."
end
