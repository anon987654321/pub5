# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml release by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e19666af459c91e8
require_relative "master/lib/master"

Law.define(:CHECK_RELEASE) do
  source "pub4 MASTER/checks/checks.yml release"
  practice "Check release holds: pub4 check release (release.rb)"
end
