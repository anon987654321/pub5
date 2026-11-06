# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:308 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 78bfd6d4e9ef14e5
require_relative "master/law/practice"

Law.define(:PROBE_BEFORE_SHIP) do
  source "MASTER constitution; OpenBSD release engineering"
  practice <<~TEXT
    pin one immutable SHA before release preflight. Required CI and preflight
    attestations must name that exact SHA, every deploy phase must use it, and
    the receipt must record it. A missing, stale or different attestation blocks
    release. After an OPENBSD/ or MASTER/web/ edit, run bin/probe integrity
    before declaring done. An unrun measurement is INCONCLUSIVE, never PASS.
  TEXT
  fix "pin one SHA, prove that exact revision, deploy only it, record its receipt, and run the owning integrity probe."
  bad  "declares done after an edit or deploys a revision other than the one proven"
  good "CI, preflight, deployment receipt and post-deploy checks name the same revision"
end
