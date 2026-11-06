# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:526 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 728f86ced21c6769
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FORM_FOLLOWS_FUNCTION) do
          tags %i[DESIGN AESTHETIC]
          fix "decorative empty wrappers without content/role"
          bad %(<div class="decor"></div>\n)
          good %(<div class="decor"><%= yield %></div>\n)
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            scan_lines(src, /<div\s+class=["'][^"']*(?:decor|ornament|spacer|filler|gradient-bg)[^"']*["']\s*>\s*<\/div>/i,
              message: "decorative empty div - form follows function; remove or attach semantics")
          end
        end
      end
    end
  end
end
