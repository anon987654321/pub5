# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1725 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 07ef0c6ef31b7179
require_relative "master/law/universal"

Law.define(:PROSE_ONE_TOPIC_PARAGRAPH) do
  source "Strunk, Elements of Style - paragraph as the unit"
  ask "Does a paragraph mix unrelated topics or bury its main point below secondary detail?"
  fix "Give each paragraph one controlling topic and state its point early."
  bad <<~'X'
    The paragraph opens with deployment history, then discusses pricing, then explains the test failure.
  X
  good <<~'X'
    The paragraph opens with the test failure and explains its cause and fix.
  X
end
