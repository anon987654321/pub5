# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/meta.rb:317 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bc391cae66d4839e
require_relative "master/law/meta"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:LEARNED_SMELLS) do
          detector LearnedSmellsLaw
          tags %i[LEARNED_SMELLS SESSION]
          fix "session-learned smell patterns from laws.yml"
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
