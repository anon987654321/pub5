# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml KIND_EXEMPLAR by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f135a6d06ef743c6
require_relative "master/lib/master"

Law.define(:KIND_EXEMPLAR) do
  source "pub4 MASTER/data/laws.yml KIND_EXEMPLAR"
  practice "An exemplar file written to be caught by a detector. A review expires in 90 days."
end
