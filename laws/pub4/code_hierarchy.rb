# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural_questions.rb:185 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 24ae10afc34c97a3
require_relative "master/law/structural_questions"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:CODE_HIERARCHY) do
          detector CodeHierarchyLaw
          tags %i[ARCHITECTURE HIERARCHY]
          fix "related classes are grouped under clear namespaces"
          proved_by "test/test_scan_law_contracts.rb"
        end
      end
    end
  end
end
