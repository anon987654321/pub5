# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural_questions.rb:213 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 909557be9111a64d
require_relative "master/law/structural_questions"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:LONG_PARAMETER_LIST) do
          detector LongParameterListLaw
          tags %i[BLOATERS API]
          fix "methods accept at most four parameters"
          proved_by "test/test_scan_law_contracts.rb"
        end
      end
    end
  end
end
