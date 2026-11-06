# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Report when done by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 265a3b20cab5bb19
require_relative "master/lib/master"

Law.define(:AGENT_MARK_ANYTHING_YOU_DIDN_T) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Report when done"
  practice "- Mark anything you didn't run as NOT_RUN."
end
