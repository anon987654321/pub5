# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml browser_policy by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f173bd45cdb242ca
require_relative "master/lib/master"

Law.define(:CHECK_BROWSER_POLICY) do
  source "pub4 MASTER/checks/checks.yml browser_policy"
  practice "Check browser_policy holds: browser policy intact"
end
