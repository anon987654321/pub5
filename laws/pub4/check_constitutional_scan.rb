# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml constitutional_scan by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f8d753b05c7cf233
require_relative "master/lib/master"

Law.define(:CHECK_CONSTITUTIONAL_SCAN) do
  source "pub4 MASTER/checks/checks.yml constitutional_scan"
  practice "Check constitutional_scan holds: Constitutional scan preflight completed."
end
