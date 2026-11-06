# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:14 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 18c7fc5ab6a43be1
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:HTML_LANG) do
          tags %i[ACCESSIBILITY]
          fix "lang attribute on <html>"
          bad %(<html>\n)
          good %(<html lang="nb">\n)
          check do |src, path|
            next [] unless src.match?(/<html\b/i)
            scan_lines(tag_source(src), /<html(?!\s+[^>]*lang=)/, message: "<html> missing lang= attribute")
          end
        end
      end
    end
  end
end
