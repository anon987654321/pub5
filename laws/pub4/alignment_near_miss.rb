# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:120 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8c8b8d5e4d9347bc
require_relative "master/law/rendered"

module Law
  Law.define(:ALIGNMENT_NEAR_MISS) do
    F.rendered(self, :ALIGNMENT_NEAR_MISS,
               source: "Mueller-Brockmann, Grid Systems (1981); Ruder, Typography (1967); Vignelli on grids",
               fix: "Put every text and media block on one edge (one padding token); keep a phone to three left edges.",
               bad: F.page(F.edge("h2.title", 16), F.edge("p.meta", 18)),
               good: F.page(F.edge("h2.title", 16), F.edge("p.meta", 16)))
  end
end
