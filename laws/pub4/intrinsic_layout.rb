# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:144 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ed69f6a66ac72244
require_relative "master/law/css"

Law.define(:INTRINSIC_LAYOUT) do
  source "Modern CSS intrinsic layout - web.dev Learn CSS"
  ask "Does the layout solve content and component sizing with fixed dimensions or breakpoint patches where intrinsic sizing could express the relationship?"
  fix "Prefer min/max-content, fit-content, auto, flex/grid, clamp(), and content-sized controls before adding fixed dimensions or breakpoint overrides."
  bad "card { width: 420px; }"
  good "card { width: min(100%, 28rem); }"
end
