# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:86 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 76da1250aede2ba3
require_relative "master/law/html"

Law.define(:BUTTON_OVER_ANCHOR) do
  source "WAI-ARIA Authoring Practices - button vs link (W3C)"
  detect { |line| line.match?(/<a\s+href=["']#["']/) }
  fix "Use <button>. Accessible by default."
  bad  "<a href=\"#\">Open</a>"
  good "<button type=\"button\">Open</button>"
end
