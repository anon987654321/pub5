# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural_questions.rb:464 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 78d0949dcda28b54
require_relative "master/law/structural_questions"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:LAZY_CLASS) do
          detector LazyClassLaw
          tags %i[DISPENSABLES SRP]
          source "Refactoring - Lazy Class (Fowler)"
          ask "Is this class too small or trivial to justify a separate abstraction boundary?"
          fix "Inline or merge it unless the boundary provides independent value."
          bad <<~'X'
          class NameHelper; def call(x); x.name; end; end
          X
          good <<~'X'
          user.name
          X
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
