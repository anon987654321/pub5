# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:67 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 24d4d56aaae909b1
require_relative "master/law/universal"

Law.define(:MOBILE_ACCESSIBILITY_DEFAULTS) do
  source "WCAG 2.2 and W3C mobile guidance"
  ask <<~'ASK'.strip
    Does a mobile-first web change fail to reflow at 320 CSS pixels, hide keyboard focus, rely on pointer-only interaction, or ignore reduced motion?
  ASK
  practice "Mobile-first means content and interaction survive narrow viewports, zoom, keyboard navigation, assistive technology, and touch."
  fix <<~'FIX'.strip
    Require reflow without loss at 320 CSS pixels except for genuinely two-dimensional content. Meet WCAG 2.2's 24 by 24 CSS pixel
    pointer-target criterion and its exceptions; prefer 44 CSS px for primary touch controls where the layout allows. Keep focus visible
    and unobscured, labels and accessible names present, keyboard paths complete, and nonessential motion responsive to
    prefers-reduced-motion. Use logical properties and intrinsic layouts; use safe-area insets and dynamic viewport units with sensible fallbacks.
  FIX
  bad <<~'X'
    width: 100vw; height: 100vh; outline: none; animation: entrance 600ms;
  X
  good <<~'X'
    max-inline-size: 100%; min-height: 100vh; min-height: 100dvh; :focus-visible has an outline; reduced motion has a fallback.
  X
end
