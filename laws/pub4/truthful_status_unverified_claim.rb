# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml TRUTHFUL_STATUS_unverified_claim by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7a58681bf8e1ea89
require_relative "master/lib/master"

Law.define(:TRUTHFUL_STATUS_UNVERIFIED_CLAIM) do
  source "pub4 MASTER/data/laws.yml TRUTHFUL_STATUS_unverified_claim"
  practice "A claim about state with no evidence of its class."
end
