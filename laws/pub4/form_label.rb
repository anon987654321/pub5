# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:233 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 122dfe4402b4cd65
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FORM_LABEL) do
          tags %i[ACCESSIBILITY]
          fix "inputs require labels or aria-label"
          bad %(<input type="text" name="query">\n)
          good %(<label>Search<input type="text" name="query"></label>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            scan_lines(control_source(src), /<input\s+(?![^>]*(?:type=["']hidden|aria-label|aria-labelledby|id=))/i,
              message: "input missing label association - add <label for> or aria-label")
          end
        end
      end
    end
  end
end
