# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml first_screen by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2518f7ed6b205f4c
require_relative "master/lib/master"

Law.define(:CHECK_FIRST_SCREEN) do
  source "pub4 MASTER/checks/checks.yml first_screen"
  practice "Check first_screen holds: ok: first-screen markers present, tap minimum declared"
end
