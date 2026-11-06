# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml EVIDENCE_SCORING by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 88c3d52390e20b58
require_relative "master/lib/master"

Law.define(:EVIDENCE_SCORING) do
  source "pub4 MASTER/data/laws.yml EVIDENCE_SCORING"
  practice "Test pass, scan clean, and code review each contribute; the threshold is all three. No margin, no partial credit."
end
