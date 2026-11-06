# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural_questions.rb:370 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 044bca89ab378ff5
require_relative "master/law/structural_questions"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:COUPLER_SMELLS) do
          detector CouplerLaw
          tags %i[COUPLING DEMETER]
          fix "inappropriate intimacy through reflective access"
          proved_by "test/test_scan_law_contracts.rb"
        end
      end
    end
  end
end
