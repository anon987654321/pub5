# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml scale_ratchet by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: cc075b1fef4ddcdb
require_relative "master/lib/master"

Law.define(:CHECK_SCALE_RATCHET) do
  source "pub4 MASTER/checks/checks.yml scale_ratchet"
  practice "Check scale_ratchet holds: Spacing, leading, radius and weight are on the declared scale."
end
