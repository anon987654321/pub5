# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml browser_diagnostics by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5a70ea30cdd8e6fd
require_relative "master/lib/master"

Law.define(:CHECK_BROWSER_DIAGNOSTICS) do
  source "pub4 MASTER/checks/checks.yml browser_diagnostics"
  practice "Check browser_diagnostics holds: ok: Chromium diagnostics recorded for the RAILS route inventory"
end
