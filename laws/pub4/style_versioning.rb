# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STYLE_VERSIONING by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 278cf1081fc1269d
require_relative "master/lib/master"

Law.define(:STYLE_VERSIONING) do
  source "pub4 MASTER/data/laws.yml STYLE_VERSIONING"
  practice "Released style versions are write-once; changes mint a higher version with owner, rationale and predecessor while prior versions remain resolvable."
end
