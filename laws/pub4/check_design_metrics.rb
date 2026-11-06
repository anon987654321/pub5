# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml design_metrics by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 78572ab7321c5544
require_relative "master/lib/master"

Law.define(:CHECK_DESIGN_METRICS) do
  source "pub4 MASTER/checks/checks.yml design_metrics"
  practice "Check design_metrics holds: design_metrics: ok"
end
