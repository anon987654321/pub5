# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml master_web_assets by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 26683f8fbe58bb4b
require_relative "master/lib/master"

Law.define(:CHECK_MASTER_WEB_ASSETS) do
  source "pub4 MASTER/checks/checks.yml master_web_assets"
  practice "Check master_web_assets holds: MASTER/web assets check passed (assets required assets present)."
end
