# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml VISUAL_DISCLOSURE_PROMINENCE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7a8a5f10ac221d76
require_relative "master/lib/master"

Law.define(:VISUAL_DISCLOSURE_PROMINENCE) do
  source "pub4 MASTER/data/laws.yml VISUAL_DISCLOSURE_PROMINENCE"
  practice "Native and affiliate creatives identify their commercial nature near the content with readable, contrasting disclosure."
end
