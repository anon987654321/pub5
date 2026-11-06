# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:312 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d9c20681a5fa5223
require_relative "master/law/html"

Law.define(:SKIP_TO_MAIN) do
  path "/app/views/layouts/"
  source "WCAG 2.4.1 Bypass Blocks / style.yml accessibility"
  scope :file
  detect { |text| text.match?(/<body\b/) && !text.match?(/skip|#main-content/) }
  fix "Add a skip link to #main-content in the layout."
  bad  "<body><nav></nav><main></main></body>"
  good "<body><a href=\"#main-content\">skip</a><main id=\"main-content\"></main></body>"
end
