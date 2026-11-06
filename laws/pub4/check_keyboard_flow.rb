# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml keyboard_flow by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 96723104e196a99d
require_relative "master/lib/master"

Law.define(:CHECK_KEYBOARD_FLOW) do
  source "pub4 MASTER/checks/checks.yml keyboard_flow"
  practice "Check keyboard_flow holds: ok: keyboard tab order is sound"
end
