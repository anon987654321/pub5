# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml PROPORTION_eight_px_rhythm by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 778df9b5e3a055d1
require_relative "master/lib/master"

Law.define(:PROPORTION_EIGHT_PX_RHYTHM) do
  source "pub4 MASTER/data/laws.yml PROPORTION_eight_px_rhythm"
  practice "Vertical spacing not on the 8px base."
end
