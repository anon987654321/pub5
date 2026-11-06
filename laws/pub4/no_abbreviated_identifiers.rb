# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/cosmetic.rb:144 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ca89d017cabb7446
require_relative "master/law/cosmetic"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:NO_ABBREVIATED_IDENTIFIERS) do
          tags %i[STYLE]
          fix "spell identifiers in full - no tmp/idx/cfg/ctx"
          bad "def call(tmp)\nend\n"
          good "def call(temporary_path)\nend\n"
          check do |src, path|
            src.each_line.with_index(1).filter_map do |line, number|
              next if line.strip.start_with?("#", "//")
              next unless line.match?(ABBREV_IDENT_RE)
              finding(line: number, message: "abbreviated identifier - spell it out (temporary_path not tmp)")
            end
          end
        end
      end
    end
  end
end
