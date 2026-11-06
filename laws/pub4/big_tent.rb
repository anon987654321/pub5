# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:492 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4f157b4c5d643f77
require_relative "master/law/universal"

Law.define(:BIG_TENT) do
  source "Push Up a Big Tent (Rails Doctrine, DHH)"
  ask "Does this unnecessarily exclude contributors through needless cleverness, jargon, or unexplained conventions?"
  fix "Prefer clear language and approachable structure without lowering technical rigor."
  bad <<~'X'
    raise Foo::Bar::Baz unless x && y && z
  X
  good <<~'X'
    raise InvalidState, "x requires y and z" unless x && y && z
  X
end
