# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:152 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 52f3308163713725
require_relative "master/law/javascript"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:CONST_BY_DEFAULT) do
          tags %i[IMMUTABLE]
          fix "use const unless reassigned"
          bad "let total = 0\n"
          good "let total = 0\ntotal += 1\n"
          check do |src, path|
            next [] if path.to_s.match?(VENDORED_JS_RE)

            lines = src.lines
            lines.each_with_index.filter_map do |line, idx|
              match = line.match(/\blet\s+([A-Za-z_$][\w$]*)\s*=/)
              next unless match

              name = Regexp.escape(match[1])
              tail = line[match.end(0)..].to_s
              rest = lines[(idx + 1)..].join
              reassigned = tail.match?(/\b#{name}\s*(?:[+\-*\/%&|^]?=|\+\+|--)/) ||
                           rest.match?(/\b#{name}\s*(?:[+\-*\/%&|^]?=|\+\+|--)/)
              next if reassigned

              finding(line: idx + 1, message: "let - use const unless value is reassigned")
            end
          end
        end
      end
    end
  end
end
