# frozen_string_literal: true

require_relative "audit"
require_relative "review"

module Fix
  module Visual
    # The simplify stage (pub4 d7314bf0ec, operator 2026-11-06), subtractive
    # only: rule blocks with identical bodies become one selector list, a
    # literal equal to a declared custom property becomes that property, a
    # bare div around one element goes. Some count must fall (selectors,
    # distinct values, wrapper divs, DOM depth, lines) or it is refused; no
    # changed pixel is kept; a visible change goes to the independent
    # reviewer and is put back unless approved.
    module Simplify
      RULE = /(?<selectors>[^{}]+)\{(?<body>[^{}]*)\}/
      WRAPPER = Regexp.new('<div>\s*(?<inner><(?<tag>\w+)\b[^>]*>(?:(?!<\k<tag>\b).)*?</\k<tag>>)\s*</div>', Regexp::MULTILINE)
      TOKEN = /(--[\w-]+)\s*:\s*([^;{}]+);/
      DECLARATION = /(?<![\w-])([a-z][\w-]*)\s*:\s*([^;{}]+);/
      SHEETS = 4

      module_function

      def counts(html: "", css: "")
        rows = { selectors: css.scan(RULE).sum { |selectors, _| selectors.split(",").size },
                 values: Census.counts(css).values.sum, wrappers: html.scan(WRAPPER).size, depth: depth(html),
                 lines: css.lines.count { |line| !line.strip.empty? } }
        rows.merge(total: rows.values.sum)
      end

      def depth(html)
        level = 0
        html.scan(%r{<(/?)\w+[^>]*?(/?)>}).map { |closing, empty| level += closing.empty? ? (empty.empty? ? 1 : 0) : -1 }.max.to_i
      end

      def reduce(html: "", css: "") = { html: unwrap(html), css: tokenise(merge(css)) }

      def unwrap(html)
        loop do
          reduced = html.gsub(WRAPPER) { Regexp.last_match[:inner] }
          return reduced if reduced == html

          html = reduced
        end
      end

      def merge(css)
        rules = css.to_enum(:scan, RULE).map { Regexp.last_match }
        repeated = rules.group_by { |rule| rule[:body].split(";").map { |p| p.strip.squeeze(" ") }.reject(&:empty?).sort }
                        .values.select { |same| same.size > 1 }
        repeated.reduce(css) do |text, same|
          joined = same.map { |rule| rule[:selectors].strip }.join(", ")
          text = same.drop(1).reduce(text) { |out, rule| out.sub(rule[0], "") }
          text.sub(same.first[0], "#{joined} {#{same.first[:body]}}")
        end
      end

      def tokenise(css)
        tokens = css.scan(TOKEN).to_h { |name, value| [value.strip.downcase, name] }
        css.gsub(DECLARATION) do |written|
          prop, value = Regexp.last_match.captures
          name = tokens[value.strip.downcase]
          name ? "#{prop}: var(#{name});" : written
        end
      end

      def verdict(before:, after:, changed_pixels:)
        return :refused unless after[:total] < before[:total]

        changed_pixels&.zero? ? :accepted : :review
      end

      # shots: ->(path) { [[before, after], ...] PNG pairs, taken around the yield }, or nil when nothing renders.
      # review: ->(group, regions) { :approved or why not }. commit: ->(path) { ... }.
      class Stage
        def initialize(world:, shots:, review:, commit:)
          @world = world
          @shots = shots
          @review = review
          @commit = commit
        end

        def run(sheets)
          sheets.sort_by { |path| [path.include?("/shared/") ? 0 : 1, path] }.first(SHEETS).to_h { |path| [path, sheet(path)] }
        end

        def sheet(path)
          before = @world.read(path).force_encoding("UTF-8")
          after = Simplify.reduce(css: before)[:css]
          return :nothing_to_remove if after == before

          pairs = @shots.call(path) { @world.write(path, after) }
          @world.write(path, after) if pairs.nil?
          settle(path, before, after, pairs)
        end

        def settle(path, before, after, pairs)
          changed = pairs&.sum { |one, two| PixelMatch.compare(one, two)[:pixel_diff_count].to_i }
          verdict = Simplify.verdict(before: Simplify.counts(css: before), after: Simplify.counts(css: after), changed_pixels: changed)
          if verdict == :accepted || (verdict == :review && approved?(path, pairs))
            @commit.call(path)
            return :applied
          end

          @world.write(path, before)
          verdict == :refused ? :no_count_fell : :visible_change_not_approved
        end

        def approved?(path, pairs)
          return false unless pairs&.any?

          one, two = pairs.first
          group = Group.new(key: "simplify #{path}", law: "AESTHETIC_MINIMALISM", place: path, surfaces: [],
                            evidence: ["simplify #{path}"], before: one, after: two)
          @review.call(group, PixelMatch.compare(one, two)[:regions]) == :approved
        end
      end
    end
  end
end
