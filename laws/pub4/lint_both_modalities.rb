# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINT_BOTH_MODALITIES by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0fea7a28609d9ed8
require_relative "master/lib/master"

Law.define(:LINT_BOTH_MODALITIES) do
  source "pub4 MASTER/data/laws.yml LINT_BOTH_MODALITIES"
  practice "Every law names a mechanical and a semantic detector. A detector declared human is a gap, counted by the duality ratchet."
end
