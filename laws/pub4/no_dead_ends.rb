# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:125 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d06324ac2f4c94ff
require_relative "master/law/practice"

Law.define(:NO_DEAD_ENDS) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    every closed door names an adjacent open one.
  TEXT
  fix "every closed door names an adjacent open one."
  bad  "cannot do that"
  good "cannot do that; here is the adjacent thing I can"
end
