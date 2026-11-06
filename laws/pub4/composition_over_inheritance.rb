# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1293 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 27fe662a7c64e70e
require_relative "master/law/universal"

Law.define(:COMPOSITION_OVER_INHERITANCE) do
  source "Design Patterns (Gang of Four)"
  ask "Is inheritance being used mainly for code reuse rather than a genuine substitutability relationship?"
  fix "Prefer composition when behavior can vary independently of type identity."
  bad <<~'X'
    class JsonReport < Report; end
  X
  good <<~'X'
    class Report; def initialize(formatter:); @formatter = formatter; end; end
  X
end
