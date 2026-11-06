# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:530 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 063d8b840ece2890
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:NO_GOD_CLASS) do
          detector GodClassLaw
          tags %i[SOLID SRP]
          source "Refactoring code smell: Large Class / God Object (Fowler)"
          ask "Does one class accumulate unrelated responsibilities that should have separate owners?"
          fix "Decompose into focused objects with explicit responsibilities."
          bad <<~'X'
          class Application; def users; end; def billing; end; def render; end; def mail; end; end
          X
          good <<~'X'
          class Users; end; class Billing; end
          X
          proved_by "test/test_scan_law_contracts.rb"
        end
      end
    end
  end
end
