# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:509 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 88b049860282b565
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:NO_ASCII_LINE_ART) do
    tags %i[BE_CONCISE]
    fix "ASCII divider decorations"
    bad "# --- section\n"
    good "# -- section\n"
    check do |src, path|
      # A test carries dividers as data — a YAML fixture's `---`, an expected
      # banner — so in a test only a comment line is read, and a section divider
      # there is the same decoration it is in lib/.
      in_test = path.to_s.match?(%r{(^|/)(test|spec)/})

      divider = /(?:^|\s)(?:={3,}|-{3,}|_{3,})(?:\s|$)/
      scan_lines(src, divider, message: "remove ASCII divider decorations").reject do |finding|
        line = src.lines[finding[:line].to_i - 1].to_s
        in_test && !line.lstrip.start_with?("#", "//") ||
          path.to_s.end_with?(".yml", ".yaml") && line.strip == "---" ||
          line.match?(/\b(assert|refute|expect|must_|wont_)/) ||
          line.match?(IDENTITY_COMPARISON)
      end
    end
  end
      end
    end
  end
end
