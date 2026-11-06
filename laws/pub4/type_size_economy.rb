# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:76 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e65723ad2b6f7380
require_relative "master/law/rendered"

module Law
  Law.define(:TYPE_SIZE_ECONOMY) do
    F.rendered(self, :TYPE_SIZE_ECONOMY,
               source: "Vignelli, The Vignelli Canon (2010), one or two sizes; Bringhurst 3.1.1; " \
                       "operator 2026-11-06: four sizes, two weights",
               fix: "Set the screen in the four shared_chrome sizes (meta, body, title, display) and two weights.",
               bad: F.page(*F.sizes(11, 12, 13, 15, 16, 18)), good: F.page(*F.sizes(13, 16, 20, 28)))
  end
end
