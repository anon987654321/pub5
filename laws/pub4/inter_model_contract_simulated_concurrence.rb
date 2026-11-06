# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml INTER_MODEL_CONTRACT_simulated_concurrence by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3643a8c27bf808a2
require_relative "master/lib/master"

Law.define(:INTER_MODEL_CONTRACT_SIMULATED_CONCURRENCE) do
  source "pub4 MASTER/data/laws.yml INTER_MODEL_CONTRACT_simulated_concurrence"
  practice "A peer turn repeated after invalidity reported as agreement."
end
