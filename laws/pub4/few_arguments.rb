# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1880 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: cf93cbc242636011
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FEW_ARGUMENTS) do
          tags %i[SMALL_PARTS]
          fix "ideal is zero to two positional arguments"
          bad "def place(north, east, depth)\nend\n"
          good "def place(north:, east:, depth:)\nend\n"
          check do |src, path|
            lines = src.lines

            lines.each_with_index.filter_map do |line, index|
              next unless line.match?(/\bdef\s+\w+\(/)
              args = line[/\(([^)]*)\)/, 1].to_s.split(",").map(&:strip)
              positional = args.reject { |arg| arg.empty? || arg.start_with?("*", "&") || arg.include?(":") || arg.include?("=") }
              next unless positional.size >= 3

              finding(line: index + 1, message: "3+ positional args - use keyword arguments or a value object",
                      blast_radius: signature_radius(lines, index))
            end
          end
        end
      end
    end
  end
end
