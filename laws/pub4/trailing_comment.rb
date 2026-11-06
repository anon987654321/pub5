# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:450 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4b9f5bac3fed59db
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:TRAILING_COMMENT) do
    tags %i[BE_CONCISE]
    fix "trailing comment after code"
    bad "value = 1 # why one\n"
    good "# why one\nvalue = 1\nvalue = 2 # scan: intentional - the exemption is not the defect\n"
    check do |src, path|
      src.each_line.with_index(1).filter_map do |line, n|
        next if line.strip.start_with?("#")

        # A line keeps its finding when a second trailing comment survives the
        # marker's removal; it loses it when the marker was the whole of it.
        next unless without_scan_marker(line).match?(/\S\s+#\s+\S/)

        finding(line: n, message: "trailing comment - promote above the line or delete")
      end
    end
  end
      end
    end
  end
end
