# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:527 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: dce4a03ed46598c3
require_relative "master/law/practice"

Law.define(:FLAT_HIERARCHY) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Flat Hierarchy - aggressive merge/rename on every write; paths are dense
    Rails-parameterize slugs (snake_case, Strunk-clean tokens); no main, misc,
    util, helper or abbreviation filler; fold *_support into parents and
    extend an existing check rather than adding a script; lib/ depth 4 unless
    the domain warrants more.
  TEXT
  fix "Flat Hierarchy - aggressive merge/rename on every write;"
  bad  "lib/misc/util_helper.rb"
  good "lib/deploy/domain_alignment.rb"
end
