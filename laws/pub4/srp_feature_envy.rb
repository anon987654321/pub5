# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SRP_feature_envy by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3fb87e3a9df009a3
require_relative "master/lib/master"

Law.define(:SRP_FEATURE_ENVY) do
  source "pub4 MASTER/data/laws.yml SRP_feature_envy"
  practice "A method that reaches into another object's data more than its own."
end
