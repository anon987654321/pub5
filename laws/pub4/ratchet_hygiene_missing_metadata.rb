# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_HYGIENE_MISSING_METADATA by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1968c884aa2cad9b
require_relative "master/lib/master"

Law.define(:RATCHET_HYGIENE_MISSING_METADATA) do
  source "pub4 MASTER/data/laws.yml RATCHET_HYGIENE_MISSING_METADATA"
  practice "A law missing statement, severity, resolution, or a node-or-root."
end
