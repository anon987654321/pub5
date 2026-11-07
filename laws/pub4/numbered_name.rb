# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/naming.rb:155 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 869789340c21ad8f
require_relative "master/law/naming"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:NUMBERED_NAME) do
          detector NumberedNameLaw
          tags %i[DOMAIN_LANGUAGE LOAD_BEARING_NAMES]
          fix "numbered siblings name no difference between themselves"
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
