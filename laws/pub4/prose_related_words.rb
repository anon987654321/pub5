# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1713 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b786e937cba25711
require_relative "master/law/universal"

Law.define(:PROSE_RELATED_WORDS) do
  source "Strunk, Elements of Style - keep related words together"
  ask "Is a modifier or subject separated from its referent so the sentence misreads on the first pass?"
  fix "Keep words that belong together close enough that the intended relation is immediate."
  bad <<~'X'
    The operator, after checking the logs carefully, restarted the service.
  X
  good <<~'X'
    After checking the logs carefully, the operator restarted the service.
  X
end
