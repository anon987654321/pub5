# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml POLA by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b0d2dd49a2a763dc
require_relative "master/lib/master"

Law.define(:POLA) do
  source "pub4 MASTER/data/laws.yml POLA"
  practice "Principle of Least Astonishment. A system behaves the way a person who has not read the source will expect. If a necessary feature astonishes, redesign the feature rather than document the surprise."
end
