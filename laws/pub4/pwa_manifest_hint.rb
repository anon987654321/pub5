# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:861 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: afd41f53b184a082
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:PWA_MANIFEST_HINT) do
          tags %i[RAILS PWA]
          fix "PWA surfaces declare manifest"
          example_path "/repo/app/views/layouts/application.html.erb"
          bad "<html>\n<head><title>Brgen</title></head>\n</html>\n"
          good %(<html>\n<head><link rel="manifest" href="/manifest.json"></head>\n</html>\n)
          check do |src, path|
            next [] unless path.to_s.match?(/layout|application\.html|manifest/i)

            if path.to_s.end_with?(".erb", ".html") && src.match?(/<html/i)
              next [] if src.match?(/rel=["']manifest["']|webmanifest/i)
              [finding(line: 1, message: "layout missing web app manifest link (PWA convention)")]
            else
              []
            end
          end
        end
      end
    end
  end
end
