# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:501 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 742623e20f1a7e48
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:TYPE_TITLE_TOKEN) do
          tags %i[DESIGN TYPOGRAPHY]
          fix "page titles use --text-title token not raw 20px"
          bad ".page-header h1 { font-size: 20px; }\n"
          good ".page-header h1 { font-size: var(--text-title, 1.25rem); }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            findings = []
            src.each_line.with_index(1) do |line, num|
              next if line.strip.start_with?("//", "/*", "*")
              next unless line.match?(/\.page-header\s+h1|page-header h1|sidebar-card h3/i) ||
                          (line.match?(/font-size\s*:\s*20px/i) && src.lines[[num - 3, 0].max...num].join.match?(/h1|title|header/i))

              if line.match?(/font-size\s*:\s*20px/i)
                findings << finding(
                  line: num,
                  message: "raw 20px title - use var(--text-title, 1.25rem) (design_rules.ui_polish.type_tokens)",
                )
              end
            end
            findings
          end
        end
      end
    end
  end
end
