# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ABSTRACTION_leaky_boundary by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ec89c297fec7b034
require_relative "master/lib/master"

Law.define(:ABSTRACTION_LEAKY_BOUNDARY) do
  source "pub4 MASTER/data/laws.yml ABSTRACTION_leaky_boundary"
  practice "A boundary that requires the caller to know the implementation."
end
