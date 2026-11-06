# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:208 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d839db98c5a26215
require_relative "master/law/css"

Law.define(:MOTION_ACCESSIBILITY) do
  source "Web accessibility and reduced motion - web.dev"
  ask "Does motion ignore the user's reduced-motion preference or animate a state whose continuity can be communicated without motion?"
  fix "Respect prefers-reduced-motion and keep transitions short, purposeful, and nonessential."
  bad ".page { animation: zoom 2s infinite; }"
  good "@media (prefers-reduced-motion: reduce) { * { animation-duration: 1ms; } }"
end
