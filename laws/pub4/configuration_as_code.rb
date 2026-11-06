# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:356 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3c72e6befa1b229e
require_relative "master/law/practice"

Law.define(:CONFIGURATION_AS_CODE) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    runtime-read material lives in data files, not prose. Top-level READMEs
    are one-paragraph stubs pointing at runtime truth. When behaviour changes,
    refresh the stub in the same commit.
  TEXT
  fix "runtime-read material lives in data files, not prose."
  bad  "behaviour described in a README"
  good "behaviour in a data file the runtime reads"
end
