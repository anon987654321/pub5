# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:248 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2605dadf3a819094
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:ASYNC_STATUS) do
          tags %i[ACCESSIBILITY]
          fix "async regions expose status for screen readers"
          bad %(<turbo-frame id="feed"></turbo-frame>\n)
          good %(<turbo-frame id="feed" aria-live="polite"></turbo-frame>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            # data-controller alone is not asynchrony: a theme toggle or a logo
            # mounts a controller and loads nothing. Only a turbo frame swaps
            # content in later, so only a turbo frame owes a status surface.
            next [] unless src.match?(/data-turbo-frame|turbo-frame/i)
            next [] if src.match?(/aria-live|role=["']status|loading|spinner|progress/i)
            [finding(line: 1, message: "async UI without aria-live/status - expose progress within 100ms")]
          end
        end
      end
    end
  end
end
