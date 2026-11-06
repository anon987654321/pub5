# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural_questions.rb:427 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 88b2bf563590123f
require_relative "master/law/structural_questions"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FEATURE_ENVY) do
          detector FeatureEnvyLaw
          tags %i[COUPLING DEMETER]
          source "Refactoring - Feature Envy (Fowler)"
          ask "Is this method more interested in another object's data than its own?"
          fix "Move the behavior toward the data it operates on or extract a suitable collaborator."
          bad <<~'X'
          def total(order); order.items.sum { |i| i.price * i.qty }; end
          X
          good <<~'X'
          class Order; def total; items.sum { |i| i.price * i.qty }; end; end
          X
          proved_by "test/test_feature_envy_law.rb"
        end
      end
    end
  end
end
