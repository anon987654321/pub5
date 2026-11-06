# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Read the manual first (operator, 2026-11-06) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 258d528eea730e90
require_relative "master/lib/master"

Law.define(:AGENT_BEFORE_EDITING_RAILS_OR_MASTER) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Read the manual first (operator, 2026-11-06)"
  practice "- Before editing RAILS/ or MASTER/web: read the latest Rails style guide (github.com/rubocop/rails-style-guide) and the Rails edge guides (edgeguides.rubyonrails.org) for every API you touch."
end
