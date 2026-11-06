# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:292 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 23962a049d2630cf
require_relative "master/law/html"

Law.define(:SEMANTIC_ELEMENTS) do
  source "HTML5 semantics / WCAG 1.3.1 (W3C)"
  detect { |line| line.match?(/<div\s+class="(header|footer|nav|main|sidebar|article|section)"/) }
  fix "Use <header>, <footer>, <nav>, <main>, <aside>, <article>, <section>."
  bad  "<div class=\"header\">"
  good "<header>"
end
