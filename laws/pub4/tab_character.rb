# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/cosmetic.rb:242 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f10b9e9dc1d28df3
require_relative "master/law/cosmetic"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:TAB_CHARACTER) do
          tags %i[HYGIENE]
          fix "tabs forbidden - use two spaces"
          bad "def call\n\tvalue\nend\n"
          good "def call\n  value\nend\n"
          check do |src, path|
            next [] if path.to_s.end_with?(".tsv") || TAB_DELIMITED_BASENAMES.include?(File.basename(path.to_s))

            scan_lines(src, /\t/, message: "tab character - indent with two spaces")
          end
        end
      end
    end
  end
end
