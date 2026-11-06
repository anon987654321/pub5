# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml human_walkthrough by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 35c6763a5ed83c93
require_relative "master/lib/master"

Law.define(:CHECK_HUMAN_WALKTHROUGH) do
  source "pub4 MASTER/checks/checks.yml human_walkthrough"
  practice "Check human_walkthrough holds: Human walkthrough check passed for apps Rails apps."
end
