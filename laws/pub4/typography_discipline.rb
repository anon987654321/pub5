# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:2039 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 726dc6b8ab064d95
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:TYPOGRAPHY_DISCIPLINE) do
          tags %i[TYPOGRAPHY]
          fix "hierarchy via weight and brightness, not decoration"
          bad "# ╭──── section ────╮\n"
          good "| name | purpose |\n|------|---------|\n"
          check do |src, path|
            scan_lines(src, BOX_DRAWING, message: "box drawing - use whitespace and typographic weight instead")
          end
        end
      end
    end
  end
end
