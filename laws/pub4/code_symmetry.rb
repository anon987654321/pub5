# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/cosmetic.rb:378 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2466541f168f28e5
require_relative "master/law/cosmetic"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:CODE_SYMMETRY) do
          tags %i[BEAUTY]
          fix "source symmetry - avoid jagged indentation shifts"
          bad "def foo\n        return true\nend\n"
          good "def foo\n  return true\nend\n"
          check do |src, path|
            findings = []
            lines = src.lines
            lines.each_with_index.each_slice(2) do |pair|
              next unless pair.size == 2
              l1, l2 = pair[0][0], pair[1][0]

              line2_number = pair[1][1]
              # a jagged shift is a sudden jump of 4+ spaces for a single line
              indent1 = l1[/\A\s*/].size
              indent2 = l2[/\A\s*/].size
              l2_stripped = l2.strip

              if (indent1 - indent2).abs >= 4 && l2_stripped.size < 40 &&
                 l2_stripped.match?(/^(?:return|break|next|raise)/)
                findings << finding(line: line2_number + 1, message: "jagged symmetry - align this line with its block")
              end
            end
            findings
          end
        end
      end
    end
  end
end
