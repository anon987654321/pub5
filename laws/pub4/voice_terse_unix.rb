# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:632 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1602caf5cc045f0c
require_relative "master/law/practice"

Law.define(:VOICE_TERSE_UNIX) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Unix voice - one job per unit, silence on success, composable lines, no
    corporate filler. Operator replies use plain English with proper casing;
    kernel and dmesg stay lowercase terse.
  TEXT
  fix "Unix voice - one job per unit, silence on success, composable lines, no corporate filler."
  bad  "a summary after a successful command"
  good "silence on success"
end
