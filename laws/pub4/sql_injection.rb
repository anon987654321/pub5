# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:2261 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 45f5d46bff0d3a90
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:SQL_INJECTION) do
          tags %i[SECURITY]
          fix "parameterize all SQL - never interpolate user input"
          bad %q(conn.execute("DELETE FROM #{table}")) + "\n"
          good %q(conn.execute("DELETE FROM #{conn.quote_table_name(table)}")) + "\n"
          check do |src, path|
            # The two fixtures above are SQL injection and its fix, spelled out in
            # this file, so this rule reads its own source as two findings unless
            # it skips the directory it lives in. COMPLETION_THEATER carries the
            # same skip for the same reason.
            src.each_line.with_index(1).filter_map do |line, n|
              stripped = line.strip
              next if stripped.start_with?("#")

              # The concatenation branch wanted a closed string before the `+` and
              # never asked for one, so it read `execute("SELECT a + b FROM t")` —
              # SQL arithmetic — as concatenation, and missed
              # `execute("SELECT * FROM " + name)`, which is the shape it is for.
              match = stripped.match(/\.(?:execute|query)\s*\(.*#\{/) ||
                      stripped.match(/\.(?:execute|query)\s*\(\s*["'][^"']*["']\s*\+/)
              next unless match

              interpolated = stripped.scan(INTERPOLATION).flatten
              next if interpolated.any? && interpolated.all? { |expr| expr.strip.match?(QUOTED_INTERPOLATION) }
              # A real `.execute(`/`.query(` call is never itself quoted string content —
              # skip when it sits inside a string literal (e.g. a human-readable label
              # like "Foo.execute(#{bar})" passed to a logger), which reads as an odd
              # number of open quote characters before the match on this line.
              prefix = stripped[0...match.begin(0)]
              next if prefix.count('"').odd? || prefix.count("'").odd?

              finding(line: n, message: "SQL injection risk - use parameterized queries or ActiveRecord helpers")
            end
          end
        end
      end
    end
  end
end
