# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml HOIST by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: db4799f5cf3ab599
require_relative "master/lib/master"

Law.define(:HOIST) do
  source "pub4 MASTER/data/laws.yml HOIST"
  practice "Lift a shared value to its owner before merging its consumers."
end
