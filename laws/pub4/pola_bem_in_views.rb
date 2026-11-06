# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml POLA_bem_in_views by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bdc9659c5b78e41e
require_relative "master/lib/master"

Law.define(:POLA_BEM_IN_VIEWS) do
  source "pub4 MASTER/data/laws.yml POLA_bem_in_views"
  practice "A view class that does not follow block-element-modifier."
end
