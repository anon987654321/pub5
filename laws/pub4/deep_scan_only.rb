# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:517 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c902781f41a704af
require_relative "master/law/practice"

Law.define(:DEEP_SCAN_ONLY) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Fixed Point - deep scan only; quick and standard depths forbidden.
  TEXT
  fix "Fixed Point - deep scan only;"
  bad  "a quick scan"
  good "a deep scan"
end
