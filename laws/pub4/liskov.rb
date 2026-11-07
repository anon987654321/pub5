# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:784 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 69ba87ad75e12980
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:LISKOV) do
          detector LiskovLaw
          tags %i[SOLID LSP]
          source "Liskov Substitution Principle (Barbara Liskov, 1987)"
          ask "Does a subtype violate assumptions or guarantees established by the type it replaces?"
          fix "Make subtype behavior satisfy the established contract or use a different abstraction."
          bad <<~'X'
          class ReadOnlyStore < Store; def save(x); raise "no"; end; end
          X
          good <<~'X'
          class ReadOnlyStore < ReadStore; end
          X
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
