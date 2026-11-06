# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml POLA_intuitive_navigation by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5f1bd954176e9e0e
require_relative "master/lib/master"

Law.define(:POLA_INTUITIVE_NAVIGATION) do
  source "pub4 MASTER/data/laws.yml POLA_intuitive_navigation"
  practice "A reader cannot predict where the next thing lives."
end
