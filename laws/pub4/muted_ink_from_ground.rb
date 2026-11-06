# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:220 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1d56732855f594e1
require_relative "master/law/rendered"

module Law
  Law.define(:MUTED_INK_FROM_GROUND) do
    band = [30, 60, 160, 1]
    F.rendered(self, :MUTED_INK_FROM_GROUND,
               source: "Refactoring UI: no grey text on coloured backgrounds; Albers on colour relativity",
               fix: "On a coloured ground, mute the ink with an opacity token (0.6/0.8) or the ground's own hue.",
               bad: F.page(F.el("p.meta", color: [153, 153, 153, 1], own_ground: band)),
               good: F.page(F.el("p.meta", color: [255, 255, 255, 0.8], own_ground: band)))
  end
end
