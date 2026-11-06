# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:2303 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ea15d576e8d8510f
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:CONTROL_CHARS) do
          tags %i[ROBUSTNESS]
          fix "no non-printable control characters in source"
          bad "value = 1\u0001\n"
          good "value = 1\t\n"
          check do |src, path|
            # Only tab (9), newline (10), and carriage return (13) are legal in
            # source. A stray SOH/NUL reads fine in most viewers but breaks parsing
            # or a byte-compare silently — corruption from a concurrent write or a
            # tool that left a sentinel byte behind. Checked by ordinal so this rule
            # carries no control character of its own.
            src.each_line.with_index(1).filter_map do |line, number|
              next unless line.each_char.any? { |char| ord = char.ord; ord < 9 || (ord > 13 && ord < 32) || ord == 127 }

              finding(line: number, message: "control character in source - corruption, remove it")
            end
          end
        end
      end
    end
  end
end
