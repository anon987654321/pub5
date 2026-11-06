# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:342 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4d63000c265f2827
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FOCUS_VISIBLE) do
          tags %i[ACCESSIBILITY]
          fix "interactive surfaces expose visible focus"
          example_path "/repo/app/assets/stylesheets/application.scss"
          bad ".btn:hover { background: var(--hover); }\n"
          good ".btn:hover { background: var(--hover); }\n.btn:focus-visible { outline: 2px solid; }\n"
          check do |src, path|
            next [] unless path.match?(/application|_minimal|_tokens|layout/i)
            next [] unless src.match?(/:hover|button|a\s*\{|\.btn/)
            next [] if src.match?(/:focus-visible|:focus\b/)
            [finding(line: 1, message: "interactive styles without :focus-visible - keyboard users need visible focus")]
          end
        end
      end
    end
  end
end
