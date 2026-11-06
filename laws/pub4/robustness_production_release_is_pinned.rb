# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_production_release_is_pinned by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 21bae557b33a9c0c
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_PRODUCTION_RELEASE_IS_PINNED) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_production_release_is_pinned"
  practice "A production release moves between revisions, or the deployed revision differs from the one proved by its required attestations."
end
