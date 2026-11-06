# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:168 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 541dcd24412a79f7
require_relative "master/law/css"

Law.define(:NATIVE_DISCLOSURE) do
  source "Popover and dialog - web.dev Learn CSS"
  ask "Does the interface recreate a disclosure, popover, or dialog primitive with unnecessary custom state and positioning?"
  fix "Prefer semantic dialog, popover, details, and native open-state behavior when their contracts match the interaction."
  bad ".menu.is-open { display: block; }"
  good "[popover]:popover-open { ... }"
end
