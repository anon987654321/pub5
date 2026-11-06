# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:411 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 76cca220cbfd3e71
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:TYPE_HIERARCHY) do
          tags %i[DESIGN TYPOGRAPHY]
          fix "modular type scale - flag one-off font sizes"
          bad ".s1 { font-size: 11px; }\n.s2 { font-size: 12px; }\n.s3 { font-size: 13px; }\n.s4 { font-size: 14px; }\n.s5 { font-size: 15px; }\n.s6 { font-size: 16px; }\n.s7 { font-size: 17px; }\n.s8 { font-size: 18px; }\n.s9 { font-size: 19px; }\n"
          good ".s1 { font-size: 11px; }\n.s2 { font-size: 12px; }\n.s3 { font-size: 13px; }\n.s4 { font-size: 14px; }\n.s5 { font-size: 15px; }\n.s6 { font-size: 16px; }\n.s7 { font-size: 17px; }\n.s8 { font-size: 18px; }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            sizes = src.scan(/font-size\s*:\s*([\d.]+)px/i).flatten.map(&:to_f)
            next [] if sizes.size < 5

            unique = sizes.uniq
            next [] if unique.size <= 8

            [finding(line: 1, message: "#{unique.size} distinct px font sizes - prefer modular scale (Müller-Brockmann: one scale, few steps) <=8 sizes (design_rules.type_scale)")]
          end
        end
      end
    end
  end
end
