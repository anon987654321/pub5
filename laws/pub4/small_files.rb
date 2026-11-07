# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:398 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9c2512a4d74e84af
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:SMALL_FILES) do
          detector SmallFilesLaw
          tags %i[SMALL_PARTS]
          fix "files under 300 lines"
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
