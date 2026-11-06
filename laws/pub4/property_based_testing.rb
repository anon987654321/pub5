# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:870 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: beb5e15d95976356
require_relative "master/law/universal"

Law.define(:PROPERTY_BASED_TESTING) do
  source "Property-based testing - QuickCheck"
  ask "Do tests check only a few examples when the important invariant can be stated as a property?"
  fix "State the invariant and exercise many generated cases."
  bad <<~'X'
    assert_equal 3, normalize("abc").length
  X
  good <<~'X'
    assert normalize(x).length <= x.length
  X
end
