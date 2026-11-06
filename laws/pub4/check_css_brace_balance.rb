# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml css_brace_balance by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 706879681c23c7f4
require_relative "master/lib/master"

Law.define(:CHECK_CSS_BRACE_BALANCE) do
  source "pub4 MASTER/checks/checks.yml css_brace_balance"
  practice "Check css_brace_balance holds: CSS brace balance check passed (all source stylesheets)."
end
