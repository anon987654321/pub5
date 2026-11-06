# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1063 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 234e38d808e68716
require_relative "master/law/universal"

Law.define(:LEVELS_OF_SCALE) do
  source "Christopher Alexander - levels of scale"
  ask "Does the design jump abruptly between granularities without useful intermediate levels?"
  fix "Introduce meaningful intermediate structure where it clarifies the whole."
  bad <<~'X'
    system with one 500-line method and 2-line helpers
  X
  good <<~'X'
    system with workflow -> stage -> operation
  X
end
