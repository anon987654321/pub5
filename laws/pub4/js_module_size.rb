# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:267 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8d3febe30c131ce6
require_relative "master/law/javascript"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:JS_MODULE_SIZE) do
          tags %i[SMALL_PARTS]
          fix "JS files over 300 lines - split at module boundaries"
          bad ("// line\n" * 301)
          good ("// line\n" * 300)
          check do |src, path|
            next [] if path.to_s.match?(VENDORED_JS_RE)

            line_count = src.lines.size
            next [] if line_count <= 300
            [finding(line: 1, message: "JS file #{line_count} lines - split at 300; extract cohesive modules",
                      blast_radius: Detector::SPANS_FILES)]
          end
        end
      end
    end
  end
end
