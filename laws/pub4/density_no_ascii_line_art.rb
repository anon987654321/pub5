# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_no_ascii_line_art by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 60bc549c845a9462
require_relative "master/lib/master"

Law.define(:DENSITY_NO_ASCII_LINE_ART) do
  source "pub4 MASTER/data/laws.yml DENSITY_no_ascii_line_art"
  practice "A line of asterisks is not a separator."
end
