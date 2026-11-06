# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml content_for_yield by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4453810ff4158a93
require_relative "master/lib/master"

Law.define(:CHECK_CONTENT_FOR_YIELD) do
  source "pub4 MASTER/checks/checks.yml content_for_yield"
  practice "Check content_for_yield holds: content_for_yield: every produced content slot has a consumer"
end
