# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:835 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f5cb6f881cbe93ac
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:DEPENDENCY_INVERSION) do
          detector DependencyInversionLaw
          tags %i[SOLID DIP]
          source "SOLID - Dependency Inversion Principle"
          ask "Does high-level policy directly instantiate concrete dependencies that should be replaceable?"
          fix "Depend on stable abstractions and inject concrete implementations at the boundary."
          bad <<~'X'
          class Checkout; def call; Stripe::Charge.create; end; end
          X
          good <<~'X'
          class Checkout; def initialize(payments:); @payments = payments; end; end
          X
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
