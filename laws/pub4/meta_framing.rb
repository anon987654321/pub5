# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:439 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1fb5b627e2461ec5
require_relative "master/law/practice"

Law.define(:META_FRAMING) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    after a batch, surface what is missing or structurally off rather than
    dumping an itemised diff. Close with one consolidation question. "Land
    all" means batch and commit without per-item reconfirmation.
  TEXT
  fix "after a batch, surface what is missing or structurally off rather than dumping an itemised diff."
  bad  "an itemised diff dump"
  good "what is missing, and one question"
end
