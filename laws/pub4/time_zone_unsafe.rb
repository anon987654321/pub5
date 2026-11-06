# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:468 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ecda2e1b37df525e
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:TIME_ZONE_UNSAFE) do
    tags %i[ROBUSTNESS]
    fix "bare Time.now/Date.today bypasses Rails Time.zone"
    example_path "/repo/app/models/example.rb"
    bad "stamp = Time.now.beginning_of_day\n"
    good "generated_at: Time.now.utc.iso8601, exp: Time.now.to_i\n# Date.today is the server's day\n"
    check do |src, path|
      next [] unless path.match?(%r{/app/|/spec/|/test/})

      # A comment explaining why the code avoids Date.today names it; amber's
      # PlannedOutfit did, and the rule sent it for repair. Blanking comment
      # lines keeps every line number.
      # Spaces and tabs only before the #: \s would take the newlines of the blank lines above a comment
      # with it, and every finding after it reported the wrong line.
      src = src.gsub(/^[ \t]*#.*$/, "")

      # Time.now.utc and Time.now.to_i do not read Time.zone: one converts to UTC
      # explicitly, the other is epoch seconds. Every RAILS finding this rule
      # produced was one of those two forms — JWT exp/iat, a tmpfile suffix, and
      # generated_at timestamps already pinned to .utc — so the rule was reporting
      # 13 rewrites that would have changed no behaviour at all.
      findings = scan_lines(src, /(?<![A-Za-z_.])Time\.now\b(?!\s*\.\s*(?:utc|to_i|to_f|to_r))/,
                             message: "Time.now ignores Time.zone - use Time.current")

      findings += scan_lines(src, /(?<![A-Za-z_.])Date\.today\b/,
                             message: "Date.today ignores Time.zone - use Date.current")
      findings += scan_lines(src, /(?<![A-Za-z_.])DateTime\.now\b/,
                             message: "DateTime.now - use Time.current.to_datetime")
      findings
    end
  end
      end
    end
  end
end
