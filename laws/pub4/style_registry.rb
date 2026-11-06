# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STYLE_REGISTRY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 43e0f7246bd7fabb
require_relative "master/lib/master"

Law.define(:STYLE_REGISTRY) do
  source "pub4 MASTER/data/laws.yml STYLE_REGISTRY"
  practice "Each named style resolves to one immutable versioned entry per modality; tools consume the registry instead of maintaining parallel house looks."
end
