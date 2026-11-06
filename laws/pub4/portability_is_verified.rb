# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:894 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 557d6fa316f21319
require_relative "master/law/universal"

Law.define(:PORTABILITY_IS_VERIFIED) do
  source "OpenBSD portability discipline; explicit platform contracts"
  ask "Is support claimed for an operating system, release, architecture or runtime that has not been exercised, or does a platform-specific assumption leak across its boundary?"
  practice "Portability is a measured promise, not an inference from POSIX-like spelling. Keep platform-specific behavior at narrow edges and verify every named target."
  fix "Name supported targets, isolate platform-specific interfaces behind small adapters, and run native checks on every claimed target. An unavailable target is INCONCLUSIVE, never PASS."
  bad "It works on Linux, so the OpenBSD path is presumed correct."
  good "OpenBSD and macOS behavior are explicit; each declared target runs its own relevant contract checks."
end
