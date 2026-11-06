# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:290 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bc79205ef7cbd89c
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:DATA_CLASS) do
          detector DataClassLaw
          tags %i[SRP SOLID]
          source "Refactoring - Data Class (Fowler)"
          ask "Does this class mainly hold data while behavior that belongs with that data is scattered across other modules?"
          fix "Move cohesive behavior toward the data owner or replace the holder with a meaningful domain abstraction."
          bad <<~'X'
          class Money; attr_reader :cents; end; Tax.total(money)
          X
          good <<~'X'
          class Money; attr_reader :cents; def taxed(rate); cents * rate; end; end
          X
          proved_by "test/test_structural_shape_laws.rb"
        end
      end
    end
  end
end
