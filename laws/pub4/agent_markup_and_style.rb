# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 80f5bbc096c57e4e
require_relative "master/lib/master"

Law.define(:AGENT_MARKUP_AND_STYLE) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Markup and style.**\n  - Use semantic HTML and spelled-out class names (button, not btn).\n  - No style words in class names, and no serif fonts."
end
