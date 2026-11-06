# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:141 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d690b5fc323c0ca4
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:GRID_STRUCTURE) do
          tags %i[DESIGN LAYOUT]
          fix "grid structure - shared tracks, consistent alignment and parent-owned gap"
          ask "Does the interface express repeated relationships with coherent grid or flex tracks and parent-owned gap rather than arbitrary per-child offsets and widths?"
          # Structural question: Find grid-like containers whose direct children combine absolute positioning, a fixed physical offset and a fixed wide width.
          example_path "/repo/app/assets/stylesheets/_example.scss"
          bad ".cards > * { position: absolute; left: 17px; width: 243px; }\n"
          good ".cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 16rem), 1fr)); gap: var(--space-4); }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            clean = without_block_comments(src)
            findings = []
            clean.to_enum(:scan, /([^{}\n]+)\{([^{}]*)\}/m).each do
              match = Regexp.last_match
              selector = match[1].strip
              body = match[2]

              next unless selector.match?(/(?:grid|cards|items|results|columns|layout|feed)\b/i)
              next unless selector.match?(/>\s*\*/)
              next unless body.match?(/\bposition\s*:\s*absolute\b/i)
              next unless body.match?(/\b(?:left|right|inset-inline-start|inset-inline-end)\s*:\s*-?\d+(?:\.\d+)?px\b/i)
              next unless body.match?(/\bwidth\s*:\s*\d{3,}(?:\.\d+)?px\b/i)

              line = clean[0...match.begin(0)].count("\n") + 1
              findings << finding(
                line:,
                message: "grid-like direct children use absolute offsets and a fixed wide width - prefer shared grid/flex tracks and parent-owned gap",
              )
            end
            findings.uniq { |item| [item[:line], item[:message]] }
          end
        end
      end
    end
  end
end
