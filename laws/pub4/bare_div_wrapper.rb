# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:34 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 17fe2908eb911b5a
require_relative "master/law/html"

Law.define(:BARE_DIV_WRAPPER) do
  source "HTML5 semantics / WCAG 1.3.1 - an element with no meaning carries none"
  # A div grouping a dt/dd pair inside a <dl> is the HTML 5.2 idiom, not a
  # styling wrapper — the spec added it precisely so the pair could share a
  # layout box.
  #
  # The marker convention applies here as well: a bare div whose line carries
  # `scan: intentional` states its reason where the element lives — the grid
  # column wrapper is the layout, and the text it holds is anonymous (a
  # nickname row, a cart line) — so no semantic element would carry meaning
  # the div does not.
  detect { |line| line.match?(/<div\s*>/) && !line.match?(/<div>\s*(?:<%=\s*tag\.dt|<dt)/) && !line.match?(/scan:\s*intentional\b/) }
  fix "Name the group with a semantic element, or drop the wrapper and select its children by structure."
  bad  "<div>"
  good "<section>"
end
