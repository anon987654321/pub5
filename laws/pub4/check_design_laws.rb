# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml design_laws by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5abd3b12ae667337
require_relative "master/lib/master"

Law.define(:CHECK_DESIGN_LAWS) do
  source "pub4 MASTER/checks/checks.yml design_laws"
  practice "Check design_laws holds: ok: declared surfaces meet the rendered design-book Laws"
end
