# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml rendered_geometry by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7f6dcec92d991f2c
require_relative "master/lib/master"

Law.define(:CHECK_RENDERED_GEOMETRY) do
  source "pub4 MASTER/checks/checks.yml rendered_geometry"
  practice "Check rendered_geometry holds: ok: rendered geometry contracts satisfied"
end
