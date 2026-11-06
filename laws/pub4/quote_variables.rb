# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:188 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b10894e34273fa6b
require_relative "master/law/javascript"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:QUOTE_VARIABLES) do
          tags %i[ROBUSTNESS]
          fix "quote $variables where the shell word-splits"
          bad "#!/bin/bash\ngrep $pattern file\n"
          good "#!/bin/zsh\ngrep $pattern file\n"
          check do |src, path|
            # Quoting is a fact about the interpreter: zsh does not word-split or
            # glob an unquoted parameter expansion; sh, ksh and bash all do. The
            # deep scan's 455 zsh findings were idiomatic code flagged by a sh
            # doctrine, so the rule reads the shebang before it judges.
            shebang = src.lines.first.to_s
            next [] unless shebang.match?(%r{\A#!.*\b(?:sh|ksh|bash)\b}) && !shebang.include?("zsh")
            # Even where the shell splits, three shapes never do and one splits
            # on purpose: an assignment (var=$x is unsplit in every shell), a
            # [[ ]] test (ksh and bash suppress splitting inside it), text in
            # single quotes (awk positionals), and `for x in $list` (the split
            # IS the iteration). Only an unquoted expansion in argument
            # position remains — the shape that actually breaks.
            # Line-lexed, statefully: heredoc bodies and the insides of a
            # multi-line double-quoted string are text, not argument position,
            # and a per-line regex cannot know that without carrying the state.
            heredoc_end = nil
            in_dquote = false
            in_squote = false
            src.each_line.with_index(1).filter_map do |line, n|
              if heredoc_end
                heredoc_end = nil if line.strip == heredoc_end
                next
              end
              if in_squote
                in_squote = false if line.count("'").odd?
                next
              end
              if in_dquote
                in_dquote = false if line.count('"') - line.scan(/\\"/).size == 1
                next
              end
              # State first, even on lines the skips below would drop: an awk
              # program often opens its single quote on an assignment line.
              if (m = line.match(/<<-?\s*["']?(\w+)["']?/))
                heredoc_end = m[1]
              end
              bare = line.gsub(/"(?:\\.|[^"\\])*"/, '""').gsub(/'[^']*'/, "''")
                         .gsub(/\[\[.*?\]\]/, "[[]]").gsub(/\$0\b/, "")
              in_dquote = true if bare.scan(/(?<!\\)"/).size.odd?
              in_squote = true if line.gsub(/"(?:\\.|[^"\\])*"/, "").count("'").odd?
              next if in_dquote || in_squote
              next if line.lstrip.start_with?("#")
              next if line.match?(/\A\s*(?:typeset|local|export|readonly)?\s*\w+=[^=]/)
              next if line.match?(/\bfor\s+\w+\s+in\b/)
              # `case $x in` never field-splits its word; `set -- $x` IS the split.
              next if line.match?(/\bcase\s+\$\w+\s+in\b/) || line.match?(/\bset\s+--\s+\$/)
              next unless bare.match?(/(?<!\\)\$\w+/)
              # Beyond this line lexer: a nested command substitution carrying its
              # own quotes ($(field "$x" 1) inside a string) can leave one false
              # positive; shellcheck is the tool that lexes that, when it lands.
              finding(line: n, message: "unquoted $variable in argument position - word-splits in this shell; wrap in double quotes")
            end
          end
        end
      end
    end
  end
end
