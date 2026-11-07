# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:654 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5a05e5f70fd3b2c2
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:CQS) do
          detector CqsLaw
          tags %i[CQS CLEAN_CODE]
          fix "command-query separation - mutate OR return, not both"
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
