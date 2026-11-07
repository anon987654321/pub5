# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ATTESTATION_IS_NOT_FINDING by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9165913f038440b0
require_relative "master/lib/master"

Law.define(:ATTESTATION_IS_NOT_FINDING) do
  source "pub4 MASTER/data/laws.yml ATTESTATION_IS_NOT_FINDING"
  practice "An attestation is a first-person declaration whose evidence is the operator's signature, not runtime measurement. The loader records it, the trace cites it, the review does not overturn it. Presenting an attestation as a finding is a false claim about state; it is a violation of truthful_status. Presenting a finding as an attestation is the same violation from the other side."
  ask "Classify every asserted fact as runtime observation, static inspection, human attestation, inference, intended future work, or unknown. Require an operator identity/signature and timestamp for attestation; require logs/probes/test output for runtime observation. Detect any attestation presented as an instrument finding or vice versa. Abstain when provenance is missing; never let a review model overturn a valid operator attestation without explicit contradictory evidence."
end
