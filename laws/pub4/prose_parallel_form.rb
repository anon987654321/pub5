# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1701 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 97fa7497c82c0db4
require_relative "master/law/universal"

Law.define(:PROSE_PARALLEL_FORM) do
  source "Strunk, Elements of Style - coordinate ideas in similar form"
  ask "Do items in a list or series mix grammatical forms where parallel structure would make the relationship clearer?"
  fix "Use the same grammatical form for coordinated items."
  bad <<~'X'
    The system must read files, validation, and to report errors.
  X
  good <<~'X'
    The system must read files, validate input, and report errors.
  X
end
