# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1319 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 80854d07b6a9e0f6
require_relative "master/law/universal"

Law.define(:STEPDOWN) do
  source "Clean Code - Stepdown Rule"
  ask "Does the code fail to read top-down from high-level intent into progressively smaller details?"
  fix "Arrange definitions so each step introduces the detail used by the next."
  bad <<~'X'
    def helper; end; def main; helper; end
  X
  good <<~'X'
    def main; helper; end; def helper; end
  X
end
