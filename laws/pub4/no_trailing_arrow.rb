# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:355 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1ca85bbcf8c969d0
require_relative "master/law/css"

Law.define(:NO_TRAILING_ARROW) do
  source "DENSITY - a link already says it can be followed; an arrow glyph in its text adds no information"
  detect { |line| DesignMarks.arrow_label?(line) }
  fix "Write the verb and the object (\"Les saken\"); the link styling carries the affordance."
  bad  '<a href="/news">Les mer -></a>'
  good '<a href="/news">Les saken</a>'
end
