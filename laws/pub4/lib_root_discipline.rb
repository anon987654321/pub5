# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:362 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 139cad75e1f1c26f
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:LIB_ROOT_DISCIPLINE) do
          detector LibRootDisciplineLaw
          tags %i[ABSTRACTION ARCHITECTURE]
          fix "new files shouldn't land directly in lib/ root"
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
