# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BRINGHURST_line_breaks by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: acc3eecdfb66cc60
require_relative "master/lib/master"

Law.define(:BRINGHURST_LINE_BREAKS) do
  source "pub4 MASTER/data/laws.yml BRINGHURST_line_breaks"
  practice "Line break at a non-word boundary; a ragged edge treated as a saw."
end
