# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural_questions.rb:239 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fa3d7bce598840d8
require_relative "master/law/structural_questions"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:PRIMITIVE_OBSESSION) do
          detector PrimitiveObsessionLaw
          tags %i[BLOATERS DOMAIN_MODELING]
          source "Refactoring - Primitive Obsession (Fowler)"
          ask "Are primitives carrying domain rules that would be clearer and safer as a value object?"
          fix "Create a focused value object when the primitive has behavior or invariants."
          bad <<~'X'
          email = "a@b.com"; Email.send(email)
          X
          good <<~'X'
          email = EmailAddress.parse(raw); Mailer.send(email)
          X
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
