# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STEWARDSHIP_utilitas by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9d0a6fea78f86ddd
require_relative "master/lib/master"

Law.define(:STEWARDSHIP_UTILITAS) do
  source "pub4 MASTER/data/laws.yml STEWARDSHIP_utilitas"
  practice "A thing with no purpose a person can name."
end
