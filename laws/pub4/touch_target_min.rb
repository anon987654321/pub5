# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:261 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c96f15b8e51fbadd
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:TOUCH_TARGET_MIN) do
          tags %i[DESIGN UX ACCESSIBILITY]
          fix "Fitts - interactive targets >=44px"
          ask "Is the interactive element's hit area too small for comfortable thumb use?"
          # Structural question: Check if mobile-specific views lack minimum target constraints
          bad ".btn {\n  width: 12px;\n}\n"
          good ".btn {\n  width: 48px;\n}\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            min = ::Master::Review::Scan::Laws.thresholds.touch_min_px.to_i
            button_re = Master::Fix::Scan::AstFixer::WebTransforms::TOUCH_SELECTOR
            findings = []
            current_selector = ""

            src.each_line.with_index(1) do |line, num|
              # Standard SCSS puts the selector and its width/height on
              # separate lines (`.carousel-btn {` then `width: 12px;` on the
              # next) -- a same-line-only check is structurally blind to that
              # shape, which is the normal one (found 2026-07-21, empirically:
              # this exact rule missed the exact bug it exists to catch).
              # Tracks only the innermost selector, not full brace depth --
              # doesn't handle deep nesting (e.g. `&:hover {}` losing outer
              # context), but covers the common flat-block case.
              current_selector = line if line.include?("{")

              next unless line.match?(/min-(?:width|height)|height|width/i)
              next unless "#{current_selector}\n#{line}".match?(button_re) ||
                          (line.match?(/min-height|height/) && path.to_s.include?("button"))

              line.scan(Master::Fix::Scan::AstFixer::WebTransforms::TOUCH_DIMENSION) do |raw|
                px = raw[0].to_i
                next if px >= min || px.zero?

                findings << finding(line: num, message: "touch target #{px}px < #{min}px (Fitts / design_rules.ux_laws.fitts)")
              end
            end
            findings
          end
        end
      end
    end
  end
end
