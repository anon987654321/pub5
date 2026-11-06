# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/cosmetic.rb:224 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3c10a436e4914cb2
require_relative "master/law/cosmetic"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:ALL_CAPS_NO_TRACKING) do
          tags %i[TYPOGRAPHY]
          fix "all-caps labels need letter-spacing"
          bad ".label { text-transform: uppercase; }\n"
          good ".label { text-transform: uppercase; letter-spacing: 0.08em; }\n"
          check do |src, path|
            next [] unless src.match?(/text-transform:\s*uppercase/i)
            next [] if src.match?(/letter-spacing\s*:/i)
            [finding(line: 1, message: "uppercase without letter-spacing - add tracking per laws.yml")]
          end
        end
      end
    end
  end
end
