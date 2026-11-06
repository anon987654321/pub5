# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml VISUAL_RENDER_INTEGRITY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 429af539bbe578cc
require_relative "master/lib/master"

Law.define(:VISUAL_RENDER_INTEGRITY) do
  source "pub4 MASTER/data/laws.yml VISUAL_RENDER_INTEGRITY"
  practice "A creative passes only with rendered evidence proving assets loaded, transfer size within budget and layout shift within budget."
end
