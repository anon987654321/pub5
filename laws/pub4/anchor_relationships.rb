# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:176 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 16d1eccf75bb1a6b
require_relative "master/law/css"

Law.define(:ANCHOR_RELATIONSHIPS) do
  source "CSS Anchor Positioning - web.dev Learn CSS"
  ask "Is a floating element positioned relative to another element through brittle coordinates or JavaScript when their spatial relationship is stable?"
  fix "Prefer declarative anchor positioning where browser support and the interaction contract permit it."
  bad ".menu { left: 183px; top: 72px; }"
  good ".menu { position-anchor: --trigger; position-area: block-end span-inline-end; }"
end
