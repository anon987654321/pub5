# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:216 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 62d21b2e058a54cd
require_relative "master/law/css"

Law.define(:NAVIGATION_CONTINUITY) do
  source "View Transitions and Navigation API - Baseline 2026"
  ask "Does a same-origin navigation or state transition unnecessarily destroy context when continuity would make the relationship between states clearer?"
  fix "Preserve scroll, focus, state, and visual continuity first; use View Transitions or the Navigation API only when they simplify a real transition."
  bad "navigate_to(result); reset_all_page_state"
  good "navigate_to(result); preserve_context"
end
