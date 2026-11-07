# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural_questions.rb:150 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 56ec3ed3c67f9ee2
require_relative "master/law/structural_questions"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:CONFIG_HIERARCHY) do
          detector ConfigHierarchyLaw
          tags %i[CONFIG HIERARCHY]
          fix "config keys are grouped, non-duplicated, and shallow"
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
