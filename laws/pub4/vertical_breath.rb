# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/cosmetic.rb:341 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 12d4e05824a2cc29
require_relative "master/law/cosmetic"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:VERTICAL_BREATH) do
          tags %i[BEAUTY]
          fix "vertical breath - avoid 10+ statements without a blank line"
          bad (1..10).map { |i| "line#{i} = 1\n" }.join
          good "a = 1\n\nb = 2\n# a doc comment\n# runs on\n# for several\n# lines\n# above\n# the\n# def\n# it\n# names\n" \
               "def c\n  d\nend\n"
          check do |src, path|
            findings = []
            lines = src.lines
            dense_count = 0
            start_line = 1
            depth = 0

            lines.each_with_index do |line, n|
              continuing = depth.positive?
              depth = [depth + ::Master::Review::Scan::Laws.bracket_delta(line), 0].max
              if line.strip.empty?
                if dense_count >= 10
                  findings << finding(line: start_line, message: "suffocated block - add a blank line for breath")
                end
                dense_count = 0
                start_line = n + 2
              elsif !continuing && !line.match?(STATEMENT_SKIP)
                dense_count += 1
              end
            end

            # A dense block that reaches end of file without a trailing blank
            # line misses the check above — every file that reaches EOF mid-block
            # (the common case) went unreported.
            if dense_count >= 10
              findings << finding(line: start_line, message: "suffocated block - add a blank line for breath")
            end
            findings
          end
        end
      end
    end
  end
end
