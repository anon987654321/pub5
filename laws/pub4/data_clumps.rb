# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural_questions.rb:340 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: eda8fd051d25f372
require_relative "master/law/structural_questions"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:DATA_CLUMPS) do
          detector DataClumpsLaw
          tags %i[BLOATERS DOMAIN_MODELING]
          fix "the same parameters travelling together are a record struggling to be born"
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
