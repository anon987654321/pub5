# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:563 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5d131d1ae2305f57
require_relative "master/lib/master"

Law.define(:RATCHET_CSS_BUDGET) do
  source "pub4 MASTER/lib/operator/ratchets.rb:563"
  practice "css_budget's numbers need the check to run (it compiles nothing, but it does walk 94 stylesheets), so the ceiling is read here and the current value is deep-only."
end
