# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml user_flow by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b3a05278ba2660ab
require_relative "master/lib/master"

Law.define(:CHECK_USER_FLOW) do
  source "pub4 MASTER/checks/checks.yml user_flow"
  practice "Check user_flow holds: User flow + MASTER design-principle check passed."
end
