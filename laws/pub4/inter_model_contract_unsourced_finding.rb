# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml INTER_MODEL_CONTRACT_unsourced_finding by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 434100a2b7414ecd
require_relative "master/lib/master"

Law.define(:INTER_MODEL_CONTRACT_UNSOURCED_FINDING) do
  source "pub4 MASTER/data/laws.yml INTER_MODEL_CONTRACT_unsourced_finding"
  practice "A finding that names no evidence."
end
