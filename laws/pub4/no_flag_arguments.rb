# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1917 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1eb0381c491ce1c2
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:NO_FLAG_ARGUMENTS) do
          source "Clean Code - no flag arguments"
          ask "Does a boolean argument make one function perform two different jobs or select unrelated behavior?"
          tags %i[SMALL_PARTS]
          fix "Split the responsibilities into named operations or objects."
          bad "def render(body, cache = true)\nend\n"
          good "def render(body, cache: true)\nend\n"
          check do |src, path|
            src.each_line.with_index(1).filter_map do |line, n|
              next unless line.match?(/def \w+\(/)

              args_str = line[/\(([^)]*)\)/, 1].to_s
              args = args_str.split(",").map(&:strip)
              positional_bool = args.any? do |a|
                a.match?(/\A\w+\s*=\s*(true|false)\z/) && !a.include?(":")
              end
              finding(line: n, message: "boolean flag arg - split into two methods") if positional_bool
            end
          end
        end
      end
    end
  end
end
