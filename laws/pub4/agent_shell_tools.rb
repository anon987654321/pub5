# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 34fb66b2af9c4975
require_relative "master/lib/master"

Law.define(:AGENT_SHELL_TOOLS) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Shell tools.** Don't use sed, awk, tr, cut, head, tail or wc. Use Ruby, zsh or grep."
end
