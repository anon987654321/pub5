# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:188 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4bcc3feaf9667081
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:CYCLOMATIC_COMPLEXITY) do
          detector CyclomaticComplexityLaw
          tags %i[LINEARITY SMALL_PARTS]
          fix "cyclomatic complexity under 10 per method"
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
