# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/brand.rb:29 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 48532deebdaf41ff
require_relative "master/law/brand"

Law.define(:PAPER_NOT_PURE_WHITE) do
  path %r{/mrdamascy/}
  source "Bergen brand systems - paper tones, not #FFF (storefront_art matte-paper rule)"
  detect { |line| line.match?(/background(-color)?:\s*(#fff\b|#ffffff\b|white)\s*;/i) }
  fix "Paint page scopes with the paper token, never pure white."
  bad  "background: #FFFFFF;"
  good "background: var(--paper);"
end
