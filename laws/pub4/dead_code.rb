# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:742 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bf66b3da7bc906ed
require_relative "master/law/ruby"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:DEAD_CODE) do
          tags %i[CLEAN_CODE]
          fix "eliminate unreachable code"
          transform "remove_immediate_dead_code"
          bad "  return value\n  log(value)\n"
          good "  return value if done?\n  log(value)\n"
          check do |src, path|
            lines = src.lines
            lines.each_with_index.filter_map do |line, index|
              # Terminator at the line start only, and unconditional: `x = return_val`,
              # `return x if cond`, `raise unless y`, and a ternary all keep the next
              # line reachable, and `return_index` is not the keyword at all. Matching
              # a bare \b(return|raise)\b flagged every guard clause in the codebase.
              match = line.match(/\A(\s*)(return|exit|raise|throw)\b(.*)$/)
              next unless match

              indent, rest = match[1], match[3]
              next if rest.match?(/\b(if|unless)\b/) || rest.match?(/&&|\|\|/) || rest.include?("?")
              # A statement that continues (`raise "…" \`, a trailing comma or operator, an
              # open bracket) does not end on this line, so the next line is still part of it.
              next if rest.rstrip.match?(/[\\,(\[{+*\/-]\z/) || rest.count("([{") > rest.count(")]}")

              following = lines[index + 1]
              next unless following

              stripped = following.strip
              next if stripped.empty? || stripped.match?(/\A(end|else|elsif|when|in |rescue|ensure|[)\]}])/)
              # Only code at the same or deeper indent in the same block is unreachable;
              # a dedent means the terminator ended its block and the next line is not.
              next unless following[/\A */].length >= indent.length

              finding(line: index + 2, message: "unreachable code after #{line.strip}")
            end
          end
        end
      end
    end
  end
end
