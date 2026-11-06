# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROOTS_VOCABULARY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3ecfaf6e500fb22a
require_relative "master/lib/master"

Law.define(:ROOTS_VOCABULARY) do
  source "pub4 MASTER/data/laws.yml ROOTS_VOCABULARY"
  practice "The thirteen roots a universal law names."
end
