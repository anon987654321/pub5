# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/brand.rb:38 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9713a712e8b342ff
require_relative "master/law/brand"

Law.define(:PARAMETRIC_MARK_ONLY) do
  path %r{/mrdamascy/}
  source "Bergen-snittet v1 - marks derive from a parametric source, never hand-drawn"
  detect { |line| line.match?(/d="M[\d\s.,A-Za-z-]{80,}"/) }
  fix "Compose marks from the parametric constants (src/lib/marks.ts + scripts/gen-marks.mjs); short paths, named parts."
  bad  '<path d="M4 35.5 L22.5 13.5 L41 35.5 M7 43.5 H41 M34.5 9.5 m-5.5 0 a5.5 5.5 0 1 0 11 0 a5.5 5.5 0 0 0 -11 0" />'
  good "d={SOMMERSETH.roof}"
end
