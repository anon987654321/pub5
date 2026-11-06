# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml journey_invariant by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e3f1cde466c44e35
require_relative "master/lib/master"

Law.define(:CHECK_JOURNEY_INVARIANT) do
  source "pub4 MASTER/checks/checks.yml journey_invariant"
  practice "Check journey_invariant holds: ok: journey invariants hold"
end
