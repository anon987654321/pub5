# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:333 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 602c306d446d50c5
require_relative "master/law/practice"

Law.define(:RESTART_RAILS) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    one file, one restart. After a MASTER/web, live lib/ or data YAML deploy,
    restart and wait before curling. Never batch web edits behind a single
    restart at the end.
  TEXT
  fix "one file, one restart."
  bad  "five web edits, one restart at the end"
  good "one file, one restart"
end
