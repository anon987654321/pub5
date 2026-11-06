# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_comments_as_deodorant by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 28a4012d62d5adc2
require_relative "master/lib/master"

Law.define(:DENSITY_COMMENTS_AS_DEODORANT) do
  source "pub4 MASTER/data/laws.yml DENSITY_comments_as_deodorant"
  practice "A comment that restates the code."
end
