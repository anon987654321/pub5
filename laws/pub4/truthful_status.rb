# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml TRUTHFUL_STATUS by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bff6d9c2d0b3ce42
require_relative "master/lib/master"

Law.define(:TRUTHFUL_STATUS) do
  source "pub4 MASTER/data/laws.yml TRUTHFUL_STATUS"
  practice "Report observed state, not intended. A claim about state carries evidence of its class."
end
