# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STEWARDSHIP_mono_no_aware by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 37b0ff0f42805800
require_relative "master/lib/master"

Law.define(:STEWARDSHIP_MONO_NO_AWARE) do
  source "pub4 MASTER/data/laws.yml STEWARDSHIP_mono_no_aware"
  practice "A system that pretends nothing is temporary."
end
