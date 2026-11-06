# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:789 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7f4040bb7009ff4f
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:STIMULUS_PROGRESSIVE) do
          tags %i[RAILS JAVASCRIPT UX]
          fix "interactive UI should degrade without JS when possible"
          bad %(<div data-controller="map"></div>\n)
          good %(<div data-controller="map"><a href="/kart">Kart</a></div>\n)
          check do |src, path|
            next [] unless path.to_s.include?("/app/views/")

            next [] unless src.match?(/data-controller=/)
            next [] if src.match?(/<form\b|<a\s+href=|<button\b/i)
            [finding(line: 1, message: "Stimulus island without form/link fallback - progressive enhancement")]
          end
        end
      end
    end
  end
end
