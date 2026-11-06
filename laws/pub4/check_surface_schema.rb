# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml surface_schema by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 514be71bab7d5a05
require_relative "master/lib/master"

Law.define(:CHECK_SURFACE_SCHEMA) do
  source "pub4 MASTER/checks/checks.yml surface_schema"
  practice "Check surface_schema holds: surface_schema: ok"
end
