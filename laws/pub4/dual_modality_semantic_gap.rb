# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DUAL_MODALITY_semantic_gap by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 053aaee1b579f8b8
require_relative "master/lib/master"

Law.define(:DUAL_MODALITY_SEMANTIC_GAP) do
  source "pub4 MASTER/data/laws.yml DUAL_MODALITY_semantic_gap"
  practice "A law whose semantic test is human."
end
