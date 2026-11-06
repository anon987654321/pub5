# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/cosmetic.rb:201 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c9f2836f6ee952e4
require_relative "master/law/cosmetic"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:EN_DASH_RANGE) do
          tags %i[TYPOGRAPHY]
          fix "numeric ranges use en dash not hyphen"
          example_path "/repo/docs/example.md"
          bad "The band is 45-75 wide.\n"
          good "The band is 45–75 wide.\n"
          check do |src, path|
            next [] if path.end_with?(".rb", ".js", ".css", ".scss") || Law.terminal_output?(path)
            data_file = path.end_with?(".yml", ".yaml")
            src.each_line.with_index(1).filter_map do |line, number|
              stripped = line.strip

              next if stripped.start_with?("#", "//", "detect_lexical:", "- id:")
              next unless stripped.gsub(EN_DASH_NOT_A_RANGE, " ").match?(EN_DASH_RANGE_RE)
              next if stripped.match?(/^\s*-\s+\w/) # YAML list item
              # A locale's values are the copy a reader sees, so there a mapping
              # line is prose and its value is read.
              next if data_file && stripped.match?(YAML_MAPPING_LINE) && !path.include?("/config/locales/")
              finding(line: number, message: "numeric range - set an en dash (U+2013), not a hyphen")
            end
          end
        end
      end
    end
  end
end
