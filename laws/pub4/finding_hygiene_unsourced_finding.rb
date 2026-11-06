# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml FINDING_HYGIENE_unsourced_finding by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4045f04b363f5c70
require_relative "master/lib/master"

Law.define(:FINDING_HYGIENE_UNSOURCED_FINDING) do
  source "pub4 MASTER/data/laws.yml FINDING_HYGIENE_unsourced_finding"
  practice "A finding with no evidence of its class."
end
