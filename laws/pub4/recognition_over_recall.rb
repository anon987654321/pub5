# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1517 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 69a105ee9ef254c9
require_relative "master/law/universal"

Law.define(:RECOGNITION_OVER_RECALL) do
  source "Nielsen Heuristic #6 - recognition rather than recall"
  ask "Does the user need to remember information across steps that could be shown at the point of use?"
  fix "Keep relevant context, choices, and state visible where decisions happen."
  bad <<~'X'
    form.step(4) # requires remembering which file was selected
  X
  good <<~'X'
    form.step(4, file: selected_file)
  X
end
