# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:31 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: dfba7574c39fd886
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:IMG_ALT) do
          tags %i[ACCESSIBILITY]
          fix "require alt on every <img>"
          bad %(<img src="a.png">\n)
          good %(<img src="a.png" alt="a garment">\n)
          check do |src, path|
            scan_lines(tag_source(src), /<img\s+(?![^>]*alt=)/, message: "<img> missing alt= attribute")
          end
        end
      end
    end
  end
end
