# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:109 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0581496d4a46ddf8
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FILE_LAYOUT) do
          detector FileLayoutLaw
          tags %i[PROXIMITY CONVENTION]
          fix "frozen header -> requires -> module/class -> public -> private"
          proved_by "test/test_structural_shape_laws.rb"
        end
      end
    end
  end
end
