# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:432 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3350d835db282138
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:OMIT_NEEDLESS_WORDS) do
    tags %i[BE_CONCISE]
    fix "Strunk & White: omit needless words in comments"
    bad "# This is a helper for totals\n"
    good "# Sums the line items\n"
    check do |src, path|
      src.lines.each_with_index.filter_map do |line, n|
        next unless line.strip.start_with?("#")
        next if line.match?(/scan:\s*intentional\b/)

        # a wordy comment usually starts with "This is a", "Here we", "This function"
        if line.match?(/\b(?:This is a|Here we|This function|Note that)\b/i)
          finding(line: n + 1, message: "wordy comment - omit needless words")
        end
      end
    end
  end
      end
    end
  end
end
