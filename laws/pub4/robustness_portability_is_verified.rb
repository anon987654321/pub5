# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_portability_is_verified by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d5581bcaace1ff85
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_PORTABILITY_IS_VERIFIED) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_portability_is_verified"
  practice "A platform, release, architecture or runtime is declared supported without native proof for that target, or platform-specific assumptions leak across a boundary."
end
