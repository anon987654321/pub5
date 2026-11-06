# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/cosmetic.rb:405 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c7a54c16f89b0533
require_relative "master/law/cosmetic"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:TYPOGRAPHIC_GRID) do
          tags %i[TYPOGRAPHY]
          fix "typographic grid - maintain line length and vertical rhythm"
          example_path "/repo/README.md"
          bad "#{"x" * 105}\n"
          good "short line\n"
          check do |src, path|
            findings = []
            lines = src.lines

            lines.each_with_index do |line, n|
              # Bringhurst's ideal measure is ~66 characters; we allow 100 for technical prose
              if line.size > 100 && !line.match?(/\A\s*`.*`\s*\z/)
                findings << finding(line: n + 1, message: "line too long - break for typographic measure")
              end
            end
            findings
          end
        end
      end
    end
  end
end
