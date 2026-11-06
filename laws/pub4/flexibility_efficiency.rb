# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1529 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6fb0f8a5d3c440f2
require_relative "master/law/universal"

Law.define(:FLEXIBILITY_EFFICIENCY) do
  source "Nielsen Heuristic #7 - flexibility and efficiency"
  ask "Does the interface serve only novices or only experts when defaults and accelerators could coexist?"
  fix "Provide a sensible default plus efficient shortcuts for experienced users."
  bad <<~'X'
    editor = Editor.new(mode: :advanced)
  X
  good <<~'X'
    editor = Editor.new; editor.bind(:advanced, "A")
  X
end
