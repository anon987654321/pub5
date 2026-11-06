# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/brand.rb:20 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ace52916f4bdebf6
require_relative "master/law/brand"

Law.define(:SIGNAL_COLOR_NAMING) do
  path %r{/mrdamascy/}
  source "Bergen brand systems - one signal colour per identity (bob.no calibration)"
  detect { |line| line.match?(/--(accent|accent-color|secondary-color|highlight-color)\s*:/) }
  fix "Name the single signal colour --signal; no accent/secondary/highlight twins."
  bad  "--accent: #E07A00;"
  good "--signal: #C97E1E;"
end
