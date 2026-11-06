# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:213 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 79272fa5f8593773
require_relative "master/law/rendered"

module Law
  Law.define(:SMALLEST_EFFECTIVE_DIFFERENCE) do
    F.rendered(self, :SMALLEST_EFFECTIVE_DIFFERENCE,
               source: "Tufte, Visual Explanations (1997): the smallest effective difference; Envisioning Information",
               fix: "Draw structure with a 1px rule quieter than the quietest text, or with space alone.",
               bad: F.page(F.card(2, [239, 239, 239, 1])), good: F.page(F.card(1, [51, 51, 51, 1])))
  end
end
