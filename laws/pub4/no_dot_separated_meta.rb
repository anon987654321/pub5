# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:363 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: def2ee22bbbaf4b5
require_relative "master/law/css"

Law.define(:NO_DOT_SEPARATED_META) do
  source "LINEARITY - structure belongs to the element tree; glyphs between words make a flat string the reader must parse"
  detect { |line| DesignMarks.dotted_meta?(line) }
  fix "Put each fact in its own element (a list item or a span) and let spacing or a border separate them."
  bad  "<p>Bergen \u00B7 3 timer siden \u00B7 12 svar</p>"
  good "<ul class=\"meta\"><li>Bergen</li><li>3 timer siden</li><li>12 svar</li></ul>"
end
