# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:10 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 51035e85fb978abe
require_relative "master/law/html"

Law.define(:ARIA_INTERACTIVE) do
  source "WAI-ARIA (W3C) - roles for interactive elements"
  detect { |line| line.match?(/<(div|span)\s+[^>]*onclick/) }
  fix "Add role= and tabindex= for accessibility."
  bad  "<div onclick=\"go()\">"
  good "<button onclick=\"go()\">"
end
