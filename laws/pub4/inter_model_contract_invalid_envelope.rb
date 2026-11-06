# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml INTER_MODEL_CONTRACT_invalid_envelope by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 26beabeaed9bb133
require_relative "master/lib/master"

Law.define(:INTER_MODEL_CONTRACT_INVALID_ENVELOPE) do
  source "pub4 MASTER/data/laws.yml INTER_MODEL_CONTRACT_invalid_envelope"
  practice "A council turn without a validated structured request."
end
