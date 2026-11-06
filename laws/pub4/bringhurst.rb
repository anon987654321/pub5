# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BRINGHURST by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8108299a810a9a19
require_relative "master/lib/master"

Law.define(:BRINGHURST) do
  source "pub4 MASTER/data/laws.yml BRINGHURST"
  practice "The Elements of Typographic Style. Typography exists to honour content. The page is a machine for reading, and its measure, rhythm, scale, and alignment are the mechanism."
end
