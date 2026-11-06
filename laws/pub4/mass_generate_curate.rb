# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:553 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 361845a1acce8974
require_relative "master/law/universal"

Law.define(:MASS_GENERATE_CURATE) do
  source "MASTER-native (generate then curate)"
  ask "Is a high-stakes creative or design decision accepting the first plausible draft without exploring alternatives?"
  fix "Generate several materially different candidates, then curate against explicit constraints."
  bad <<~'X'
    solution = first_candidate
  X
  good <<~'X'
    solutions = generate(15); solution = curate(solutions)
  X
end
