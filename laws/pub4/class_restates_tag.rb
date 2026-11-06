# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:116 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: af2fd755f46eb631
require_relative "master/law/html"

Law.define(:CLASS_RESTATES_TAG) do
  source "style.yml bare_tag_targeting - the tag is already the name"
  detect { |line| line.match?(/<(header|footer|nav|main|section|article|aside|form|figure|dialog|details|summary|table)\b[^>]*class=["'](?:[^"']*\s)?(?:(?:content|inner|outer|wrapper|container|box|main|site|app)-)?\1(?:-(?:content|inner|outer|wrapper|container|box|area|block))?(?:\s[^"']*)?["']/) }
  fix "Drop the filler class and select the bare tag; a prefix that names which of several coexisting elements this is may stay."
  bad  "<header class=\"content-header\">"
  good "<header class=\"page-header\">"
end
