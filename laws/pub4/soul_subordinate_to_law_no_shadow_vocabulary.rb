# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SOUL_SUBORDINATE_TO_LAW_no_shadow_vocabulary by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f94ef01016611099
require_relative "master/lib/master"

Law.define(:SOUL_SUBORDINATE_TO_LAW_NO_SHADOW_VOCABULARY) do
  source "pub4 MASTER/data/laws.yml SOUL_SUBORDINATE_TO_LAW_no_shadow_vocabulary"
  practice "Soul duplicates a per-Law severity, priority, root or enforcement vocabulary owned by laws.yml."
end
