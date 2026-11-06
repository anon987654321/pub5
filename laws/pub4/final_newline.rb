# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/cosmetic.rb:254 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 55a6ec060a43d157
require_relative "master/law/cosmetic"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FINAL_NEWLINE) do
          tags %i[HYGIENE]
          fix "files end with a single newline"
          bad "puts 1"
          good "puts 1\n"
          check do |src, path|
            next [] if src.empty? || src.end_with?("\n")
            [finding(line: src.lines.size, message: "missing final newline at EOF")]
          end
        end
      end
    end
  end
end
