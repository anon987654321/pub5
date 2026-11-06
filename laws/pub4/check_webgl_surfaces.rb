# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml webgl_surfaces by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2f6a66d3a0576d9f
require_relative "master/lib/master"

Law.define(:CHECK_WEBGL_SURFACES) do
  source "pub4 MASTER/checks/checks.yml webgl_surfaces"
  practice "Check webgl_surfaces holds: ok: webgl surfaces draw"
end
