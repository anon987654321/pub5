# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:67 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a5003169d69077b7
require_relative "master/law/html"

Law.define(:BLANK_LINE_RUN) do
  source "Strunk & White I.1 - vigorous writing is concise, and so is its spacing"
  scope :file
  # Whitespace-only lines count as blank: a line holding two spaces looks
  # identical to an empty one and is the usual way a run of them survives.
  #
  # It reads comments because it measures whitespace, and the engine blanks a
  # comment to a bare newline to keep line numbers. That turns any two-line
  # comment into a run this law then reports: a four-line `<%# … %>` block
  # explaining an opt-out, with one ordinary blank line above it, was five blank
  # lines by the time the detector saw it. A spacing law that cannot see the
  # comments is measuring a file nobody wrote.
  reads_comments true
  detect { |text| text.match?(/\n[ \t]*\n[ \t]*\n/) }
  fix "Collapse consecutive blank lines to one."
  bad  "<p>first</p>\n\n\n<p>second</p>\n"
  good "<p>first</p>\n\n<p>second</p>\n"
end
