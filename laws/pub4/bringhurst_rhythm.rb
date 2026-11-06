# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BRINGHURST_rhythm by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 365de8f7dc81f624
require_relative "master/lib/master"

Law.define(:BRINGHURST_RHYTHM) do
  source "pub4 MASTER/data/laws.yml BRINGHURST_rhythm"
  practice "Rhythm not held; blank lines padding rather than separating."
end
