# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:287 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e35ff7fcc21d90bb
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:TABINDEX_ABOVE_ZERO) do
          tags %i[ACCESSIBILITY]
          fix "tabindex above zero disrupts natural tab order"
          bad %(<a href="/" tabindex="3">Home</a>\n)
          good %(<a href="/" tabindex="0">Home</a>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            scan_lines(src, /\btabindex\s*=\s*["']?[1-9]/i,
              message: "tabindex > 0 - remove or use 0/-1 with roving focus pattern")
          end
        end
      end
    end
  end
end
