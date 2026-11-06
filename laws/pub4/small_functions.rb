# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:455 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 38b5d98fc786b269
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:SMALL_FUNCTIONS) do
          detector SmallFunctionsLaw
          tags %i[SMALL_PARTS]
          fix "methods under 10 lines ideal, max 20"
          proved_by "test/test_scan_law_contracts.rb"
        end
      end
    end
  end
end
