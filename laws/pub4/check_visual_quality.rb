# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml visual_quality by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3cdf1ffce078336b
require_relative "master/lib/master"

Law.define(:CHECK_VISUAL_QUALITY) do
  source "pub4 MASTER/checks/checks.yml visual_quality"
  practice "Check visual_quality holds: visual_quality: ok"
end
