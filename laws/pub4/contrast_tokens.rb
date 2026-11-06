# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:429 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 821bfa18e02cf1c5
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:CONTRAST_TOKENS) do
          tags %i[DESIGN ACCESSIBILITY]
          fix "prefer token colors over low-contrast gray-on-gray magic"
          bad ".meta { color: #ccc; }\n"
          good ".meta { color: var(--text-secondary); }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            findings = []
            src.each_line.with_index(1) do |line, num|
              next unless line.match?(/color\s*:\s*#([0-9a-f]{3,8})/i)
              hex = line[/color\s*:\s*#([0-9a-f]{3,8})/i, 1].to_s
              next if hex.empty?
              # crude: light gray text
              next unless hex.match?(/\A([ef]{3}|[ef]{6}|ccc|ddd|eee)\z/i)

              # …but light text is only low-contrast against a light background, and
              # this read the foreground alone. #navBar declares `background-color:
              # #131921` and `color: #fff` on adjacent lines — white on near-black,
              # about 17:1 — and was reported as low-contrast. Every finding here was
              # light-on-dark. If the enclosing block sets a dark background, the pair
              # is the high-contrast case and saying otherwise is backwards.
              next if dark_background_near?(src, num)

              findings << finding(line: num, message: "low-contrast light gray text ##{hex} - use semantic token with AAA body contrast")
            end
            findings
          end
        end
      end
    end
  end
end
