# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml cross_app by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e73c92c21f0f5386
require_relative "master/lib/master"

Law.define(:CHECK_CROSS_APP) do
  source "pub4 MASTER/checks/checks.yml cross_app"
  practice "Check cross_app holds: ok: shared chrome agrees across apps"
end
