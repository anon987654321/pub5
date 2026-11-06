# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml generated_asset by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 386f2fd71859cb73
require_relative "master/lib/master"

Law.define(:CHECK_GENERATED_ASSET) do
  source "pub4 MASTER/checks/checks.yml generated_asset"
  practice "Check generated_asset holds: Generated asset freshness check passed for apps Rails apps."
end
