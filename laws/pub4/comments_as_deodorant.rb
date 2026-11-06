# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/cosmetic.rb:295 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 98c802d85858950c
require_relative "master/law/cosmetic"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:COMMENTS_AS_DEODORANT) do
          source "Refactoring - comments as deodorant (Fowler/Beck)"
          ask "Is a comment compensating for code or prose that could instead be rewritten to make the intent obvious?"
          tags %i[CLEAN_CODE SELF_EXPLAINING]
          fix "Refactor the underlying artifact first; keep comments for rationale that cannot be encoded directly."
          bad "# increment the wear count\nincrement_wear_count\n"
          good "# a torn hem is still a wearing\nincrement_wear_count\n"
          check do |src, path|
            next [] unless %w[ruby].include?(language(path))
            lines = src.lines
            lines.each_with_index.filter_map do |line, index|
              next unless line.strip.start_with?("#")
              next if line.include?("frozen_string_literal") || line.strip.start_with?("#!")

              code = lines[index + 1].to_s
              next if code.strip.empty? || code.strip.start_with?("#", "end")

              said = Laws.content_words(line.sub(/^\s*#\s*/, ""))
              next if said.size < COMMENT_RESTATEMENT_FLOOR

              shared = (said & Laws.content_words(code)).size
              next if shared.to_f / said.size < COMMENT_RESTATEMENT_RATIO

              finding(line: index + 1,
                      message: "comment restates the line below it - delete it, or say why instead of what")
            end
          end
        end
      end
    end
  end
end
