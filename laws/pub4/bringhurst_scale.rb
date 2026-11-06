# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BRINGHURST_scale by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 28fa82a3a3c2c933
require_relative "master/lib/master"

Law.define(:BRINGHURST_SCALE) do
  source "pub4 MASTER/data/laws.yml BRINGHURST_scale"
  practice "More than two weights on a terminal; emphasis louder than structure."
end
