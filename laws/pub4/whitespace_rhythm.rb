# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:390 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b5d590156bfb5b5b
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:WHITESPACE_RHYTHM) do
          tags %i[DESIGN AESTHETIC]
          fix "ma - breathing room via gap/section spacing tokens"
          bad ".card { color: red; }\n"
          good ".card { gap: var(--sp); }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            # The keyword has to be a selector this file styles, not a word anywhere
            # in it. brgen's application.scss is a list of @use lines and nothing
            # else; it was reported for lacking section spacing because one of the
            # partials it imports is named _marketplace_cards. A file with no
            # declaration block cannot have spacing to set.
            next [] unless src.include?("{")
            next [] unless src.match?(/^[^{}\n]*\b(section|hero|card|panel|main)\b[^{}\n]*\{/i)
            next [] if src.match?(/gap\s*:|section.*padding|padding-block|margin-block/i)

            [finding(line: 1, message: "layout surface without gap/section spacing - set rhythm tokens (design_rules negative_space)")]
          end
        end
      end
    end
  end
end
