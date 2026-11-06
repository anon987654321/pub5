# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural_questions.rb:281 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: cc6bdd76eb768a37
require_relative "master/law/structural_questions"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:BOOLEAN_TRAP) do
          detector BooleanTrapLaw
          tags %i[API DOMAIN_LANGUAGE]
          fix "a positional boolean parameter makes every call site a riddle"
          proved_by "test/test_smell_detectors.rb"
        end
      end
    end
  end
end
