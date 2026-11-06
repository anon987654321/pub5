# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:426 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2bdc127b877941b2
require_relative "master/law/practice"

Law.define(:UNIVERSAL_CROSS_DISCIPLINARY_RULES) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    teach the invariant once across media, then name the adapter that makes it
    concrete in each language or artifact. Separate transferable reasoning
    from local implementation and show where the analogy stops; do not force a
    false equivalence just to make one slogan fit every medium.
  TEXT
  fix "teach the invariant once; adapt the proof to each medium;"
  bad  "a slogan applied identically to unlike artifacts"
  good "one principle, explicit adapters, and an honest boundary"
end
