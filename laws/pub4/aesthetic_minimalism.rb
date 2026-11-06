# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:587 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6722142e84dc1986
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:AESTHETIC_MINIMALISM) do
          source "Nielsen Heuristic #8 - aesthetic and minimalist design"
          ask "Does this output contain information that does not earn its place for the current task?"
          tags %i[DESIGN AESTHETIC]
          fix "Remove redundant status, decoration, and secondary detail from the primary path."
          example_path "/repo/app/views/example.html.erb"
          bad %(<button class="btn"><svg class="icon"></svg><span>Save</span></button>\n)
          good %(<button class="btn">Save</button>\n)
          check do |src, path|
            next [] unless %w[html].include?(language(path))
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            scan_lines(src, /<(button|a)[^>]*>.*?<(svg|img|i)[^>]*>.*?<(span|small|badge)/im,
              message: "control packs icon+extra chrome - prefer one signal (label or icon)")
          end
        end
      end
    end
  end
end
