# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:2212 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5b0c35d278786a37
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:COMPLETION_THEATER) do
          tags %i[ROBUSTNESS COMPLETENESS]
          fix "ellipsis or etcetera as placeholder violates completeness"
          bad "handle(first, second, etc.)\n"
          good %(require "etc"\n)
          check do |src, path|
            # In prose "etc." is a word; in code it stands where the work should
            # be. Markdown is prose, and reading a documented list of examples as
            # an unfinished implementation is how a rule teaches its readers to
            # ignore it. An ellipsis still counts in both.
            prose = path.to_s.end_with?(".md", ".markdown")
            # A locale value is copy, and copy may close on three dots as well as
            # on the ellipsis: "Loading..." is a sentence trailing off, not
            # unfinished code.
            copy = path.to_s.match?(%r{/config/locales/[^/]+\.ya?ml\z})
            comment = SLASH_COMMENT_EXTENSIONS.include?(File.extname(path.to_s).downcase) ? SLASH_COMMENT : HASH_COMMENT
            src.each_line.with_index(1).filter_map do |line, n|
              stripped = line.strip

              next if stripped.start_with?("#")
              next if stripped.match?(STDLIB_ETC_REQUIRE)
              # The marker the framework advertises. scan_lines honours it and
              # this rule wrote its own loop, so the one line in the tree that
              # needs it had no way to say so.
              next if stripped.match?(/scan:\s*intentional\b/)

              code = stripped.gsub(comment, "").rstrip
              etcetera = !prose && (code.gsub(PATH_ETC, "").match?(PLACEHOLDER_ETC) || code.match?(/\betcetera\b/i))
              next unless etcetera || (!copy && code.match?(/\.\.\.\s*$/))

              finding(line: n, message: "completion theater - implement or delete, never placeholder")
            end
          end
        end
      end
    end
  end
end
