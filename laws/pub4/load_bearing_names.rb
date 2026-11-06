# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1183 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a44effce8f8eb27a
require_relative "master/law/universal"

Law.define(:LOAD_BEARING_NAMES) do
  source "Clean Code - names carry intent"
  ask "Are names vague, generic, or misleading enough that a reader cannot tell what they hold or do?"
  fix "Choose names that expose role, value, or domain meaning."
  bad <<~'X'
    data = process(input)
  X
  good <<~'X'
    normalized_invoice = normalize(input)
  X
end
