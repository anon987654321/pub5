# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:169 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bbc2b340142a3b48
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:LONG_LINE) do
    tags %i[READABILITY]
    fix "lines exceeding 120 characters"
    bad "#{"x" * 121}\n"
    good "#{"x" * 120}\n#{"x" * 100} # scan: intentional - the marker is not the defect\n"
    check do |src, path|
      next [] if path.to_s.match?(%r{/voice/personality\.rb|/io/llm\.rb})

      src.each_line.with_index(1).filter_map do |line, n|
        next unless line.chomp.length > 120
        # Measured without the marker, so exempting a line does not create a
        # finding against the exemption.
        next unless without_scan_marker(line).length > 120

        finding(line: n, message: "line #{line.chomp.length} chars (max 120)")
      end
    end
  end
      end
    end
  end
end
