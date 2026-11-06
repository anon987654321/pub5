# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_form_follows_function by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ec3921a8a419288f
require_relative "master/lib/master"

Law.define(:DENSITY_FORM_FOLLOWS_FUNCTION) do
  source "pub4 MASTER/data/laws.yml DENSITY_form_follows_function"
  practice "Decoration that does not serve a purpose."
end
