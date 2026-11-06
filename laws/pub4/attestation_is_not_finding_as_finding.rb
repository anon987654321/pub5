# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ATTESTATION_IS_NOT_FINDING_as_finding by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d297b38eb54ae96e
require_relative "master/lib/master"

Law.define(:ATTESTATION_IS_NOT_FINDING_AS_FINDING) do
  source "pub4 MASTER/data/laws.yml ATTESTATION_IS_NOT_FINDING_as_finding"
  practice "An attestation presented as a finding."
end
