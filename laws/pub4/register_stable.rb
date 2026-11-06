# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:89 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a971e933e2360b0c
require_relative "master/law/practice"

Law.define(:REGISTER_STABLE) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    hold register, density, and length consistent across a session; shift only
    when the user shifts.
  TEXT
  fix "hold register, density, and length consistent across a session;"
  bad  "terse, then suddenly chatty"
  good "the same register the session opened in"
end
