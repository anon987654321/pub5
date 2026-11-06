# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:40 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a0eed142fe9d7c70
require_relative "master/law/practice"

Law.define(:SIMPLEST_WORKS) do
  source "MASTER constitution (soul.yml absolute.rules)"
  ask "Does this unit introduce unnecessary complexity?"
  # The god-class clause this used to hold is NO_GOD_CLASS's subject, and
  # NO_GOD_CLASS detects it structurally. A practice named after one rule and
  # stating another is how a rule's findings and its prompt come apart.
  practice <<~TEXT
    fewest moving parts that solve the problem. when a simpler shape does the
    job, propose it instead of building the one you were asked for, and delete
    abstractions until it hurts.
  TEXT
  fix "Delete abstractions until it hurts. KISS."
  bad  "a factory, a registry and an adapter for one call site"
  good "the one call"
end
