# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:2109 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ea079766720a2c93
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:ONE_SOURCE) do
          source "DRY - The Pragmatic Programmer (Hunt & Thomas, 1999)"
          ask "Is the same logic or data defined in multiple authoritative places?"
          tags %i[COUPLING]
          fix "Extract one authoritative representation and make all consumers reference it."
          bad %(COUNCIL_PATH = "data/council.yml"\n)
          good "path = Master::COUNCIL_PATH\n"
          check do |src, path|
            next [] if path.to_s.include?("master.rb")
            patterns = [
              [/COUNCIL_PATH\s*=/, "define COUNCIL_PATH once in master.rb; reference Master::COUNCIL_PATH"],
              [/LAWS_PATH\s*=/, "define LAWS_PATH once in master.rb; reference Master::LAWS_PATH"],
              [/DATA_DIR\s*=\s*File\.join.*\bdata\b/, "use Master::DATA constant"],
            ]

            src.each_line.with_index(1).flat_map do |line, n|
              patterns.filter_map { |re, msg| finding(line: n, message: msg) if re.match?(line) }
            end
          end
        end
      end
    end
  end
end
