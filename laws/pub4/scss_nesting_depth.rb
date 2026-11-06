# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:839 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: dde6183cb4177b05
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:SCSS_NESTING_DEPTH) do
          tags %i[RAILS CSS DESIGN]
          fix "avoid deep SCSS nesting / preprocessor bloat"
          bad ".a {\n  .b {\n    .c {\n      .d {\n        .e {\n          color: red;\n        }\n      }\n    }\n  }\n}\n"
          good ".a {\n  .b {\n    color: red;\n  }\n}\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.rails_path?(path) || path.to_s.include?("/assets/")

            max = 0
            depth = 0

            src.each_line do |line|
              depth += line.count("{")
              depth -= line.count("}")
              depth = 0 if depth.negative?
              max = depth if depth > max
            end
            next [] if max <= 4
            [finding(line: 1, message: "SCSS nesting depth #{max} - flatten (modern CSS, no preprocessor bloat)")]
          end
        end
      end
    end
  end
end
