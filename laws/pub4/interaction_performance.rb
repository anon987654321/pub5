# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:224 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7a431f7dff9c11dc
require_relative "master/law/css"

Law.define(:INTERACTION_PERFORMANCE) do
  path "RAILS/"
  source "Web rendering performance - compositor-safe interaction motion"
  ask "Does frequent interaction motion stay on transform and opacity where possible, avoid layout properties such as top/width/height, and avoid permanent will-change or expensive visual effects?"
  fix "Animate transform and opacity for interaction feedback; let layout properties remain stable, and add will-change only around a measured animation boundary when it removes a real hitch."
  bad ".card { transition: width 300ms, top 300ms; }"
  good ".card { transition: transform var(--duration-m3-short) var(--ease-m3-spring), opacity var(--transition-fast) var(--ease-out); }"
end
