# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DUAL_MODALITY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: aa53134fad926feb
require_relative "master/lib/master"

Law.define(:DUAL_MODALITY) do
  source "pub4 MASTER/data/laws.yml DUAL_MODALITY"
  practice "Every law is enforced in both modalities. A law only mechanically enforced has a semantic gap; only semantically enforced has a mechanical gap. Both are measured; neither is zero; neither grows."
end
