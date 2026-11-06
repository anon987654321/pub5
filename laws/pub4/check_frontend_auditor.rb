# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml frontend_auditor by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6a8e6f1818699876
require_relative "master/lib/master"

Law.define(:CHECK_FRONTEND_AUDITOR) do
  source "pub4 MASTER/checks/checks.yml frontend_auditor"
  practice "Check frontend_auditor holds: auditor: 0 warnings"
end
