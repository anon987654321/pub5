# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0c341cd263452ea0
require_relative "master/lib/master"

Law.define(:AGENT_BOX_CI_GATES) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Box CI gates.** The box's CI runs these gates on every deploy, so keep them at baseline:\n  - empty_state_lint, chrome_i18n_lint, fallback_drift_lint, rubocop, brakeman, and the route manifest (`MASTER/checks/data/route_manifest.yml`).\n  - If you add a route, regenerate the manifest with `ruby MASTER/tools/rails/generate_route_manifest.rb`. It needs dev DBs and `tmp/caching-dev.txt` in each app.\n  - RAILS/test/locale_contract_test.rb requires every locale key to have a reader, and every new key to exist in both nb and en."
end
