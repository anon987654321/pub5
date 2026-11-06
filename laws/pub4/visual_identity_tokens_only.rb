# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml VISUAL_IDENTITY_TOKENS_ONLY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 13bd7e4dddc55c00
require_relative "master/lib/master"

Law.define(:VISUAL_IDENTITY_TOKENS_ONLY) do
  source "pub4 MASTER/data/laws.yml VISUAL_IDENTITY_TOKENS_ONLY"
  practice "Ad-organ CSS resolves colour, typography and spacing through the canonical visual token contract; hardcoded presentation values fail the audit."
end
