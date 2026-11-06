# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:41 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 283da4e360d286b0
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:LAZY_IMAGES) do
          tags %i[PERFORMANCE]
          fix "loading=lazy on below-fold images"
          bad %(<img src="a.png" alt="a">\n)
          good %(<img src="a.png" alt="a" loading="lazy">\n)
          check do |src, path|
            scan_lines(tag_source(src), /<img\s+(?![^>]*loading=)/, message: "<img> missing loading=lazy")
          end
        end
      end
    end
  end
end
