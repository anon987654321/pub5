# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:368 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4a6295904adcfbbf
require_relative "master/law/practice"

Law.define(:MERGE_BEFORE_MULTIPLY) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    before copying a block to vary one literal, extract or parameterise it.
    File and module sprawl is the same law one level up.
  TEXT
  fix "before copying a block to vary one literal, extract or parameterise it."
  bad  "copies the block to vary one literal"
  good "parameterises the block"
end
