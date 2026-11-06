# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:459 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fb782fd9a69fd87a
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:PIXEL_EXACT) do
          tags %i[DESIGN AESTHETIC PIXEL]
          fix "avoid subpixel/fractional layout that breaks integer grids"
          bad ".card { width: 12.5px; }\n"
          good ".card { width: 12px; }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            scan_lines(src, /(?:width|height|top|left|margin|padding|transform:\s*translate)\s*:\s*[\d.]+\.\d+px/i,
              message: "fractional px - prefer integer pixels for pixel-perfect alignment")
          end
        end
      end
    end
  end
end
