# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:147 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 81ce0a3ccdac3403
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:PREFER_TAG_HELPERS) do
          tags %i[DESIGN RAILS_IDIOM]
          fix "prefer Rails tag helpers over raw HTML wrapping a single ERB expression"
          bad %(<p><%= t("hello_world") %></p>\n)
          good %(<%= tag.p t("hello_world") %>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            scan_lines(src, SIMPLE_WRAPPER_TAG_RE,
              message: "<tag><%= ... %></tag> - prefer tag.tagname(...) (e.g. tag.p t(\"hello_world\")) so the " \
                "element and its content stay in one Ruby expression instead of splitting across ERB/HTML")
          end
        end
      end
    end
  end
end
