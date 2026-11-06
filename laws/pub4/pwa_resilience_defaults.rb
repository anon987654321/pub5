# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:87 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8a1b8304a7b21f92
require_relative "master/law/universal"

Law.define(:PWA_RESILIENCE_DEFAULTS) do
  source "MDN Progressive Web Apps and service-worker caching guidance"
  ask <<~'ASK'.strip
    Does a PWA assume optional APIs exist, offer no honest offline state, or cache or replay data without explicit freshness and safety rules?
  ASK
  practice "An installable PWA is still a web application: navigation, online failure, user data, and updates need explicit semantics."
  fix <<~'FIX'.strip
    Feature-detect optional install, sharing, storage, background, and navigation APIs and leave the primary task usable without them.
    Keep deep links and a useful offline fallback. Prefer cache-first for versioned immutable assets and network-first with a bounded timeout
    for mutable navigation/data; cache GET requests only under an explicit scope and freshness policy, never blindly cache personalized responses
    in a shared cache. Queue writes only when necessary, with visible pending state, bounded storage, same-origin validation, and idempotent replay.
    Treat a manifest, service worker, and install prompt as separate capabilities; test each supported path.
  FIX
  bad <<~'X'
    Cache every request and assume Background Sync, install prompts, and file sharing exist on all devices.
  X
  good <<~'X'
    Detect optional capabilities, cache by request type and freshness, offer an offline route, and retry only safe queued writes.
  X
end
