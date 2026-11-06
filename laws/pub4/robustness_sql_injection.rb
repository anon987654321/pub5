# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_sql_injection by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5ab3a96ccb602c5b
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_SQL_INJECTION) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_sql_injection"
  practice "A SQL call that interpolates a string."
end
