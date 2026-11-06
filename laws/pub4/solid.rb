# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SOLID by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 04252abc1b803968
require_relative "master/lib/master"

Law.define(:SOLID) do
  source "pub4 MASTER/data/laws.yml SOLID"
  practice "Five object-oriented design principles. Each exists because a class designed without it becomes brittle under the next change."
end
