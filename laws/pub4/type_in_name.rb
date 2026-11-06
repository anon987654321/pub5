# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/naming.rb:92 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8dcbcb2a22902d1f
require_relative "master/law/naming"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:TYPE_IN_NAME) do
          detector TypeInNameLaw
          tags %i[DOMAIN_LANGUAGE LOAD_BEARING_NAMES]
          fix "a name that encodes its own type says nothing the code did not"
          proved_by "test/test_smell_detectors.rb"
        end
      end
    end
  end
end
