# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:578 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a2fff6a9676d9a45
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:NESTING_DEPTH) do
          detector NestingDepthLaw
          tags %i[LINEARITY]
          fix "nesting depth under 4"
          proved_by "test/test_structural_shape_laws.rb"
        end
      end
    end
  end
end
