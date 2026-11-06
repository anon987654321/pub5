# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:443 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c1e59091f7bdc37a
require_relative "master/law/universal"

Law.define(:BEAUTIFUL_CODE) do
  source "Exalt Beautiful Code (Rails Doctrine, DHH)"
  ask "Would a reader find this merely correct rather than clear, coherent, and aesthetically deliberate?"
  fix "Rewrite for structural and aesthetic clarity, not merely passing tests."
  bad <<~'X'
    if a; b; else; c; end
  X
  good <<~'X'
    value = a ? b : c
  X
end
