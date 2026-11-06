# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_FIXTURE_DEBT_WITHOUT_FIXTURES by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5288307facf0098d
require_relative "master/lib/master"

Law.define(:RATCHET_FIXTURE_DEBT_WITHOUT_FIXTURES) do
  source "pub4 MASTER/data/laws.yml RATCHET_FIXTURE_DEBT_WITHOUT_FIXTURES"
  practice "Laws with no fixture."
end
