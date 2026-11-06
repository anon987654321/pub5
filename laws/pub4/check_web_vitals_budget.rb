# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml web_vitals_budget by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8a6324e42563f69b
require_relative "master/lib/master"

Law.define(:CHECK_WEB_VITALS_BUDGET) do
  source "pub4 MASTER/checks/checks.yml web_vitals_budget"
  practice "Check web_vitals_budget holds: ok: LCP and CLS within budget, field collection intact"
end
