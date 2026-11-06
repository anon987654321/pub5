# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:2010 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7b42263a19ce5479
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:TYPOGRAPHIC_EXCELLENCE) do
          tags %i[TYPOGRAPHY]
          fix "typographic excellence in user-facing text: the ellipsis, and a spaced en dash for an aside"
          example_path "/repo/RAILS/brgen/app/helpers/search_helper.rb"
          bad %(placeholder = "..."\n)
          good %(placeholder = "…"\n)
          check do |src, path|
            next [] if Law.terminal_output?(path)

            src.each_line.with_index(1).filter_map do |line, n|
              next if line.match?(/Open3|capture2|capture3|gsub\(|Shellwords/)
              next if line.match?(TERMINAL_PRINT)

              next if line.match?(/,\s*"--"\s*,|,\s*"--"\s*\)|<<\s*["']--/)
              # A leading-# line in an .erb file is a doc comment inside an ERB
              # block — its "..." is an example placeholder, not UI copy.
              next if path.to_s.end_with?(".erb") && line.lstrip.start_with?("#")
              next unless line.match?(/["']\.\.\.[\"']|["']--["']/)
              finding(line: n, message: "ASCII typography - the ellipsis (U+2026), or a spaced en dash for an aside")
            end
          end
        end
      end
    end
  end
end
