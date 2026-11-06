# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DUAL_MODALITY_mechanical_gap by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2b64c64ef2431a5b
require_relative "master/lib/master"

Law.define(:DUAL_MODALITY_MECHANICAL_GAP) do
  source "pub4 MASTER/data/laws.yml DUAL_MODALITY_mechanical_gap"
  practice "A law whose mechanical detector is human."
end
