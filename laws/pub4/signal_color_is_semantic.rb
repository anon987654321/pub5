# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:387 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b81f2dc87830b4bb
require_relative "master/law/css"

Law.define(:SIGNAL_COLOR_IS_SEMANTIC) do
  source "pub4 visual identity contract - signal colour is a semantic marker, never a general surface or body-text colour"
  scope :file
  detect do |text|
    unsafe_signal_background = text.scan(/([^{}]+)\{([^{}]*)\}/m).any? do |selector, declarations|
      next false unless declarations.match?(/(?:\A|;)\s*background(?:-color)?\s*:\s*var\(\s*--pub4-signal\s*\)/i)

      !selector.strip.match?(/\A#cmd-palette-list\s+li\[data-active\s*=\s*["']?1["']?\]\z/i)
    end
    direct_signal_text = text.scan(/([^{}]+)\{([^{}]*)\}/m).any? do |_selector, declarations|
      declarations.match?(/(?:\A|;)\s*color\s*:\s*var\(\s*--pub4-signal\s*\)\s*(?:!important\s*)?;/i)
    end

    unsafe_signal_background || direct_signal_text
  end
  fix "Use the signal only as a selected-state marker with explicit signal ink; use the local product accent for ordinary buttons, page surfaces and text."
  bad <<~CSS
    .hero {
      background: var(--pub4-signal);
      color: var(--pub4-signal);
    }
  CSS
  good <<~CSS
    #cmd-palette-list li[data-active="1"] {
      background: var(--pub4-signal);
      color: var(--pub4-signal-ink);
    }

    .home-feed-view.is-active {
      border-block-end-color: var(--pub4-signal);
    }

    .page {
      background: var(--surface);
      color: var(--text);
    }
  CSS
end
