# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml KIND_UNREGISTERED by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a89b1ff4e541a1af
require_relative "master/lib/master"

Law.define(:KIND_UNREGISTERED) do
  source "pub4 MASTER/data/laws.yml KIND_UNREGISTERED"
  practice "A file whose kind is not in this registry. A finding under TRUTHFUL_STATUS_dishonest_kind."
end
