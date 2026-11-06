# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:968 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 10f2b147f471134b
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:MIDDLE_MAN) do
          detector MiddleManLaw
          tags %i[ENGINEERING_FIT ABSTRACTION]
          source "Refactoring - Middle Man (Fowler)"
          ask "Does this class mostly delegate methods to another object without adding meaningful policy?"
          fix "Remove the unnecessary middle layer or give it a real abstraction."
          bad <<~'X'
          def name; @user.name; end; def email; @user.email; end
          X
          good <<~'X'
          attr_reader :user
          X
          proved_by "test/test_structural_shape_laws.rb"
        end
      end
    end
  end
end
