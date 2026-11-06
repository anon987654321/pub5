# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/shell.rb:69 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3886f9add5f9e6c8
require_relative "master/law/shell"

Law.define(:NO_INLINE_ASSETS_IN_SHELL) do
  source "RAILS/__shared frontend convention"
  detect { |line| line.match?(/<style\b|<script\b/) }
  fix "Move the markup into app/views and the style into a tracked stylesheet."
  bad  "print '<style>body{}</style>' > index.html"
  good "cp app/assets/site.css out/"
end
