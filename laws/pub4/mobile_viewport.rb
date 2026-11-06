# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:192 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f4fd9f8c7b7ddefe
require_relative "master/law/css"

Law.define(:MOBILE_VIEWPORT) do
  source "Modern viewport units - web platform"
  ask "Does a mobile layout assume a stable viewport height when browser chrome, safe areas, or the virtual keyboard can change the available space?"
  fix "Use svh, dvh, lvh, env(safe-area-inset-*), and intrinsic layout according to the actual interaction requirement."
  bad ".screen { height: 100vh; }"
  good ".screen { min-height: 100dvh; }"
end
