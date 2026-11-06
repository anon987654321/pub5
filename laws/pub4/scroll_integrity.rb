# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:200 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8ee04fa69318ff66
require_relative "master/law/css"

Law.define(:SCROLL_INTEGRITY) do
  source "CSS overflow and modern scroll containers - web.dev Learn CSS"
  ask "Does the layout create accidental page overflow, nested scroll traps, or a scroll container that breaks sticky or touch interaction?"
  fix "Give each scroll container one intentional axis and verify the rendered scroll and sticky behavior at mobile widths."
  bad ".shell { overflow: auto; }"
  good ".shell { overflow-x: clip; overflow-y: auto; }"
end
