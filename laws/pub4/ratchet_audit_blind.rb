# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_AUDIT_BLIND by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 89542fd50680890d
require_relative "master/lib/master"

Law.define(:RATCHET_AUDIT_BLIND) do
  source "pub4 MASTER/data/laws.yml RATCHET_AUDIT_BLIND"
  practice "Laws audited blind."
end
