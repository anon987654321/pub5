# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/meta.rb:445 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5bcb4f6e5a9a6995
require_relative "master/law/meta"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FILE_SPRAWL) do
          detector FileSprawlLaw
          tags %i[FLAT_HIERARCHY COLLAPSE_BEFORE_ADDING]
          source "MASTER-native - collapse before adding; flat hierarchy"
          ask "Are tiny files or one-file directories adding structure without carrying " \
              "meaningful independent responsibility?"
          fix "Absorb tiny artifacts into their natural owner before creating another boundary."
          bad <<~'X'
          lib/foo/bar.rb
          X
          good <<~'X'
          lib/foo.rb
          X
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
