# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:903 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c8dfb980d4a0aabc
require_relative "master/law/universal"

Law.define(:PRODUCTION_RELEASE_IS_PINNED) do
  source "OpenBSD release engineering; immutable revision deployment"
  ask "Can a moving branch reference change the code under deployment, or can a release be stamped without proof for the exact commit being deployed?"
  practice "Resolve one immutable commit, require preflight and CI attestations to name that commit, deploy only that pin, and record the same revision in the receipt."
  fix "Fetch once, pin the target SHA, verify ancestry and exact-SHA attestations, deploy only that SHA, and refuse a mismatch or missing required proof."
  bad "Test one revision, then deploy the later moving branch tip."
  good "CI, preflight, deployment and receipt all name the same immutable SHA."
end
