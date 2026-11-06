# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml apps_yml by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b487a1f1de5ea630
require_relative "master/lib/master"

Law.define(:CHECK_APPS_YML) do
  source "pub4 MASTER/checks/checks.yml apps_yml"
  practice "Check apps_yml holds: apps.yml validator: OK"
end
