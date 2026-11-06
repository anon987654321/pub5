# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:191 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 29e31053d8faa42c
require_relative "master/law/practice"

Law.define(:EXEMPTIONS_EXPIRE) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    an allowlist entry, baseline row or opt-out that outlives its subject is a
    hole in a check nobody can see, because the thing it excuses is invisible.
    Every exemption names what it excuses, and a check fails when the named
    thing stops existing.
  TEXT
  fix "an allowlist entry, baseline row or opt-out that outlives its subject is a hole in a check nobody can see, beca"
  bad  "an allowlist entry outliving its subject"
  good "an exemption naming what it excuses, checked"
end
