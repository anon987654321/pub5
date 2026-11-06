# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ATTESTATION_IS_NOT_FINDING_as_attestation by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5a39ec5b1a69efaf
require_relative "master/lib/master"

Law.define(:ATTESTATION_IS_NOT_FINDING_AS_ATTESTATION) do
  source "pub4 MASTER/data/laws.yml ATTESTATION_IS_NOT_FINDING_as_attestation"
  practice "A finding presented as an attestation."
end
