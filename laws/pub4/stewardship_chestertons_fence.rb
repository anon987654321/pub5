# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STEWARDSHIP_chestertons_fence by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d45d46a4e7fcb245
require_relative "master/lib/master"

Law.define(:STEWARDSHIP_CHESTERTONS_FENCE) do
  source "pub4 MASTER/data/laws.yml STEWARDSHIP_chestertons_fence"
  practice "A fence removed without naming what it kept out."
end
