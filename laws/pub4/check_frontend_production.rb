# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml frontend_production by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a308821565814a5f
require_relative "master/lib/master"

Law.define(:CHECK_FRONTEND_PRODUCTION) do
  source "pub4 MASTER/checks/checks.yml frontend_production"
  practice "Check frontend_production holds: Frontend production check passed (apps apps + MASTER/web layouts)."
end
