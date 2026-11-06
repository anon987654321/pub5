# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:2373 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d6198481604fa283
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:AUDIT_APPEND_ONLY) do
          tags %i[SECURITY]
          fix "an audit sink appends to its log and never truncates it"
          bad %Q(bus.subscribe("tool:before") { |e| record(e) }\nFile.open(@path, "w") { |f| f.puts(line) }\n)
          good %Q(bus.subscribe("tool:before") { |e| record(e) }\nFile.open(@path, "a") { |f| f.puts(line) }\n)
          check do |src, path|
            next [] unless src.match?(/subscribe\(\s*["']tool:before["']/)

            src.each_line.with_index(1).filter_map do |line, number|
              next if line.strip.start_with?("#")
              # Rotation renames; only an in-place truncation is the defect.
              next unless line.match?(/File\.open\s*\([^)]*,\s*["']w\+?["']/) ||
                          line.match?(/File\.write\s*\((?![^)]*mode:\s*["']a)/) ||
                          line.match?(/\.truncate\s*\(/)

              finding(line: number, message: %(audit log truncated - append with mode "a", or rotate by rename))
            end
          end
        end
      end
    end
  end
end
