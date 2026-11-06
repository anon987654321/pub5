# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3b8643a785b90990
require_relative "master/lib/master"

Law.define(:AGENT_RUNNING_TESTS) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Running tests.** From the export's `RAILS/<app>`, run `env -u BUNDLE_GEMFILE -u BUNDLE_PATH -u BUNDLE_APP_CONFIG PATH=\"$HOME/.rbenv/shims:$PATH\" COVERAGE=0 ruby bin/rails test <files>`. Tests default to the nb locale."
end
