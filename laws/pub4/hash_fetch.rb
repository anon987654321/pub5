# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:671 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 026b54e22f62eadb
require_relative "master/law/ruby"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:HASH_FETCH) do
          tags %i[READABILITY]
          fix "prefer Hash#fetch over [] with ||"
          bad "value = options[:size] || 10\n"
          good "value = options.fetch(:size, 10)\n"
          check do |src, path|
            src.each_line.with_index(1).filter_map do |line, n|
              stripped = line.strip
              next unless (m = stripped.match(/(@{0,2}\w+)\[:\w+\]\s*\|\|(?!=)/))
              var = Regexp.escape(m[1])
              # A genuine fetch-with-default candidate is `hash[:key] || <default>`
              # where <default> is a plain value, not another lookup. Excluded here,
              # none of which are fetch candidates: memoization (`||=`, handled by
              # the negative lookahead above); the string-or-symbol dual-key
              # fallback in either key order (`h[:k] || h["k"]` or
              # `h["k"] || h[:k]`); and a comparison chain that coincidentally
              # contains a bracket access (`a[:x] >= b[:x] ||`).
              next if stripped.match?(/#{var}\[:\w+\]\s*\|\|\s*#{var}\[/)
              next if stripped.match?(/#{var}\[["']\w+["']\]\s*\|\|\s*#{var}\[:\w+\]/)
              next if stripped.match?(/(?:>=|<=|==|!=)\s*#{var}\[:\w+\]\s*\|\|/)

              finding(line: n, message: "hash symbol lookup with fallback - prefer hash.fetch(:key, default)")
            end
          end
        end
      end
    end
  end
end
