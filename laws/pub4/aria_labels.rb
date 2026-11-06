# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:101 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f84078724d370136
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:ARIA_LABELS) do
          tags %i[ACCESSIBILITY]
          fix "interactive controls need accessible names"
          bad %(<button class="icon-only"><svg></svg></button>\n)
          good %(<button class="icon-only" aria-label="Close"><svg></svg></button>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            nameless_control_lines(src).map do |line|
              finding(line:, message: "control has no accessible name - give it text content, aria-label, " \
                                      "aria-labelledby, or an id a <label for> points at")
            end
          end
        end
      end
    end
  end
end
