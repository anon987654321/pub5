# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_HYGIENE_STATEMENT_CONFLICTS by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 18440619b3329ef2
require_relative "master/lib/master"

Law.define(:RATCHET_HYGIENE_STATEMENT_CONFLICTS) do
  source "pub4 MASTER/data/laws.yml RATCHET_HYGIENE_STATEMENT_CONFLICTS"
  practice "Two laws with conflicting statements."
end
