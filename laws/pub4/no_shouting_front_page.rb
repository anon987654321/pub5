# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:2060 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9e276f88a3da973a
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:NO_SHOUTING_FRONT_PAGE) do
          source "Operator directive 2026-11-06 - front-page headlines are never set in capitals; Bringhurst, Elements of Typographic Style 2.1.6-2.1.7 (capitals take tracking, lowercase never does)"
          ask "Is the headline a reader meets first - title page, cover, landing or document H1 - set in full capitals?"
          tags %i[TYPOGRAPHY]
          fix "Set the front-page headline in the text face: mixed case, or true small caps where the face cuts them. Tracked capitals are 2.1.6's repair for labels, not the shape a front page opens with."
          example_path "/repo/docs/example.md"
          bad "# THE ELEMENTS OF TYPOGRAPHIC STYLE\n"
          good "# The Elements of Typographic Style\n"
          check do |src, path|
            next [] unless path.to_s.match?(/\.(?:md|markdown|tex|html?|erb)\z/)

            src.each_line.with_index(1).filter_map do |line, n|
              headline = FRONT_PAGE_HEADLINE.match(line)
              next unless headline

              words = headline.captures.compact.first.to_s.gsub(FRONT_PAGE_MARKUP, " ").strip
              next if words.empty? || words.match?(/\A\S+\z/)

              upper = words.scan(/\p{Lu}/).size
              next unless upper >= 2 && upper == words.scan(/\p{L}/).size

              finding(line: n, message: "front-page headline in capitals - set it in the text face, mixed case or true small caps")
            end
          end
        end
      end
    end
  end
end
