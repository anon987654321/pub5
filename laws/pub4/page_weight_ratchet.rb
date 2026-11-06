# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:245 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5c133de0a3b79860
require_relative "master/law/rendered"

module Law
  Law.define(:PAGE_WEIGHT_RATCHET) do
    budget = { "script" => 180_000 }
    F.rendered(self, :PAGE_WEIGHT_RATCHET,
               source: "Rams, good design is environmentally friendly; Wroblewski; tokens.pwa.weight",
               fix: "Bring the route under its row in checks/data/page_weight.yml; lower the row when it drops.",
               bad: F.snap(weight: { "route" => "/", "bytes" => { "script" => 420_000 }, "budget" => budget }),
               good: F.snap(weight: { "route" => "/", "bytes" => { "script" => 150_000 }, "budget" => budget }))
  end
end
