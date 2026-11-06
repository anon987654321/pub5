# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/brand.rb:59 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 57566db6bc995b38
require_relative "master/law/brand"

Law.define(:CURSOR_NONE_REQUIRES_CURSOR) do
  source "Bergen brand systems - hiding the cursor is a promise to replace it"
  detect { |line| line.match?(/cursor:\s*none/) }
  fix "Avoid hiding the native cursor unless a replacement is rendered and gated by pointer:fine and prefers-reduced-motion; review the full component."
  bad  ".page { cursor: none; }"
  good ".page { cursor: auto; }"
end
