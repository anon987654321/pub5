# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml engine_boundaries by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e52e6b3a79b0203d
require_relative "master/lib/master"

Law.define(:CHECK_ENGINE_BOUNDARIES) do
  source "pub4 MASTER/checks/checks.yml engine_boundaries"
  practice "Check engine_boundaries holds: engine_boundaries: no engine names another's constants beyond its declared reads"
end
