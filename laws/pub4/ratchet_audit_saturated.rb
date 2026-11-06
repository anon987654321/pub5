# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_AUDIT_SATURATED by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c0d0140c91db0fda
require_relative "master/lib/master"

Law.define(:RATCHET_AUDIT_SATURATED) do
  source "pub4 MASTER/data/laws.yml RATCHET_AUDIT_SATURATED"
  practice "Laws audited saturated."
end
