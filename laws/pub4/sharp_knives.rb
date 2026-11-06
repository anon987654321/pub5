# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:455 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7e6f7734a4e7bbcb
require_relative "master/law/universal"

Law.define(:SHARP_KNIVES) do
  source "Provide Sharp Knives (Rails Doctrine, DHH)"
  ask "Does this restrict a capable operator's legitimate power mainly to guard against a rare misuse?"
  fix "Preserve useful capability; document dangerous edges and require deliberate use."
  bad <<~'X'
    raise "forbidden" if dangerous_operation?
  X
  good <<~'X'
    dangerous_operation! # explicit operator choice
  X
end
