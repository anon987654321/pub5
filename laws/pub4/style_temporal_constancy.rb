# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STYLE_TEMPORAL_CONSTANCY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 52debaee49b55b0a
require_relative "master/lib/master"

Law.define(:STYLE_TEMPORAL_CONSTANCY) do
  source "pub4 MASTER/data/laws.yml STYLE_TEMPORAL_CONSTANCY"
  practice "A render uses one style instance throughout unless a schedule hash is declared in both the registry and render manifest."
end
