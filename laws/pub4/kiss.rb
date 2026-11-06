# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:712 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 85ec57e3d380d15d
require_relative "master/law/universal"

Law.define(:KISS) do
  source "KISS - Keep It Simple"
  ask "Does this introduce complexity the problem does not require?"
  fix "Flatten the design to the simplest structure that solves the actual problem."
  bad <<~'X'
    result = strategies.fetch(mode).call(input).then { |x| wrap(x) }.then { |x| audit(x) }
  X
  good <<~'X'
    result = process(input)
  X
end
