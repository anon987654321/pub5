# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:344 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 382665fbc13208b9
require_relative "master/law/css"

Law.define(:NO_EYEBROW_LABEL) do
  source "DENSITY - a small tracked all-caps line above a heading restates the heading's role; Strunk, omit needless words"
  scope :file
  detect do |text|
    DesignMarks.eyebrow_blocks(text).any? || text.each_line.any? { |line| DesignMarks.eyebrow_class?(line) }
  end
  fix "Drop the eyebrow; let the heading and the page structure say where the reader is. A label that names a field stays."
  bad  ".kicker { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.1em; }"
  good ".field-label { font-size: 0.875rem; font-weight: 600; }"
end
