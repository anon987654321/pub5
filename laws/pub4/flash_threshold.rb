# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:237 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 398a87038f6fb5af
require_relative "master/law/rendered"

module Law
  Law.define(:FLASH_THRESHOLD) do
    F.rendered(self, :FLASH_THRESHOLD,
               source: "WCAG 2.3.1 Three Flashes or Below Threshold, A",
               fix: "Modulate brightness within 10% or dissolve slower than 3 Hz; never strobe a large area.",
               bad: F.snap(motion: { "surfaces" => [F.strobe(50)] }),
               good: F.snap(motion: { "surfaces" => [F.strobe(600)] }))
  end
end
