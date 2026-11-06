# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml page_simulation by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a1deb67a33201c69
require_relative "master/lib/master"

Law.define(:CHECK_PAGE_SIMULATION) do
  source "pub4 MASTER/checks/checks.yml page_simulation"
  practice "Check page_simulation holds: ok: page UI/UX simulations clean across inventory"
end
