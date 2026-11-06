# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:267 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ae859a9955539171
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:REDUCED_MOTION) do
          tags %i[ACCESSIBILITY]
          fix "animations respect prefers-reduced-motion"
          example_path "/repo/app/assets/stylesheets/_example.scss"
          bad "@keyframes spin { to { transform: rotate(360deg); } }\n"
          good "@keyframes spin { to { transform: rotate(360deg); } }\n@media (prefers-reduced-motion: reduce) { * { animation: none !important; } }\n"
          check do |src, path|
            next [] unless src.match?(/@keyframes|animation\s*:/i)
            # Either direction of the query satisfies this. `reduce` turns motion off
            # for people who asked; `no-preference` never turns it on for them in the
            # first place, which is the stronger form — motion is opt-in rather than
            # opt-out, so a browser that reports nothing gets the still version.
            # visualizer.css wraps every animation in `no-preference` and was the last
            # REDUCED_MOTION finding in the tree: the rule was flagging the better
            # pattern for not being the one it knew.
            next [] if src.match?(/prefers-reduced-motion:\s*(?:reduce|no-preference)/i)
            [finding(line: 1, message: "animation without prefers-reduced-motion override")]
          end
        end
      end
    end
  end
end
