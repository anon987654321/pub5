# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml occlusion by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 550e2f6d3225db22
require_relative "master/lib/master"

Law.define(:CHECK_OCCLUSION) do
  source "pub4 MASTER/checks/checks.yml occlusion"
  practice "Check occlusion holds: ok: every control answers a press at its own centre"
end
