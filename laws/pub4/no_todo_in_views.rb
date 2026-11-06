# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:115 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9beac0b864dfd38b
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:NO_TODO_IN_VIEWS) do
          tags %i[MAINTAINABILITY]
          fix "no TODO/FIXME in shipped views"
          bad %(<%# FIXME: wire the filter %>\n)
          good %(<%# the filter is Marketplace::ListingFacets %>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            scan_lines(src, /\b(TODO|FIXME|HACK)\b/, message: "unfinished marker in view - resolve before ship")
          end
        end
      end
    end
  end
end
