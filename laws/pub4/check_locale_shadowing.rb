# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml locale_shadowing by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9d96c10e4d1b84ac
require_relative "master/lib/master"

Law.define(:CHECK_LOCALE_SHADOWING) do
  source "pub4 MASTER/checks/checks.yml locale_shadowing"
  practice "Check locale_shadowing holds: locale_shadowing: ok"
end
