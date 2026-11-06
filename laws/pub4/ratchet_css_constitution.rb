# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:634 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 02120b9654074158
require_relative "master/lib/master"

Law.define(:RATCHET_CSS_CONSTITUTION) do
  source "pub4 MASTER/lib/operator/ratchets.rb:634"
  practice "css_budget's seven rules, from one check run."
end
