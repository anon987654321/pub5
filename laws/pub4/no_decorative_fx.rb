# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:52 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5e9e4d8c0a170673
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:NO_DECORATIVE_FX) do
          tags %i[DESIGN AESTHETIC PIXEL]
          fix "flat UI - no blur, glow, or ornamental shadow"
          ask "Does the element use shadows or glows that serve no functional purpose?"
          # Structural question: Check for 'glow' or 'shadow' in filenames or directory names
          example_path "/repo/app/assets/stylesheets/_example.scss"
          bad ".card { box-shadow: 0 2px 8px rgba(0,0,0,.3); }\n"
          good ".card { box-shadow: none; }\n.b { text-shadow: none; }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            findings = []
            # Block comments blanked: a rationale paragraph explaining a measured
            # value is prose, and its continuation lines do not start with * .
            without_block_comments(src).each_line.with_index(1) do |line, num|
              next if line.strip.start_with?("//", "/*", "*")

              # Allow a suppressed shadow — `none`, or an all-zero value. The old
              # pattern matched `0\s`, which is the first token of every real
              # shadow too: `box-shadow: 0 2px 8px rgba(0,0,0,.3)` was skipped as
              # if it were a suppression. Found by this rule's own fixture,
              # 2026-08-07. Match the whole value instead of its first token.
              next if line.match?(/box-shadow\s*:\s*(none|0(?:\s+0)*(?:\s+0)?)\s*(?:!important)?\s*;/i)
              next if line.match?(/text-shadow\s*:\s*(none|0(?:\s+0)*(?:\s+0)?)\s*(?:!important)?\s*;/i)

              if line.match?(/box-shadow\s*:/i) || line.match?(/text-shadow\s*:/i)
                findings << finding(line: num, message: "ornamental shadow - flat UI: use border/contrast, not glow (design_rules pixel_perfection)")
              end
              if line.match?(/filter\s*:\s*[^;]*blur\s*\(/i) || line.match?(/backdrop-filter\s*:/i)
                findings << finding(line: num, message: "blur/backdrop-filter - forbidden decorative FX for pixel-perfect flat surfaces")
              end
            end
            findings
          end
        end
      end
    end
  end
end
