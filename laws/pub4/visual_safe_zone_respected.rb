# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml VISUAL_SAFE_ZONE_RESPECTED by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b584f5aadf9fc89a
require_relative "master/lib/master"

Law.define(:VISUAL_SAFE_ZONE_RESPECTED) do
  source "pub4 MASTER/data/laws.yml VISUAL_SAFE_ZONE_RESPECTED"
  practice "Rendered headline, logo and call-to-action bounds remain inside the placement safe zone."
end
