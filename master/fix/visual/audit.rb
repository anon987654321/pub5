# frozen_string_literal: true

module Fix
  module Visual
    # What the browser computed, against the tokens (pub4 5b187ec31e,
    # fc00c9f788, c5c44bb599). Source lints read what a stylesheet wrote;
    # this reads what reached the element after rem, inheritance and the
    # cascade, from a geometry walk's element list (key, tag, text, visible,
    # frect, font_size, line_height, spacing, border_radius, bg, color,
    # text_wrap, text_lines, box_shadow). Each finding names its Law.
    #
    # tokens: { space_px: [..], line_height: [..], radius_px: [..],
    #           palette: ["#rrggbb", ..], max_font_sizes: n }
    module Audit
      LAWS = { spacing: "EIGHT_PX_RHYTHM", leading: "LINE_HEIGHT_ON_SCALE", radius: "RENDERED_VALUES",
               palette: "MAGIC_COLOR", type_pixel: "PIXEL_EXACT", type_scale: "TYPE_HIERARCHY" }.freeze
      SIDES = %w[padding-top padding-right padding-bottom padding-left margin-top margin-bottom row-gap column-gap].freeze
      HEADING = /\Ah[1-6]\z/
      BODY_SIZES_MAX = 5
      EDGE_FLOOR = 8
      VOID_SHARE = 1.0 / 3

      module_function

      def computed(surface, elements, tokens)
        shown = Array(elements).select { |el| el["visible"] }
        rows = {
          spacing: shown.flat_map { |el| off_spacing(el, tokens) },
          leading: shown.filter_map { |el| off_leading(el, tokens) },
          radius: shown.filter_map { |el| off_radius(el, tokens) },
          palette: shown.filter_map { |el| off_palette(el, tokens) },
          type_pixel: shown.filter_map { |el| fractional(el) },
          type_scale: type_scale(shown, tokens)
        }
        rows.reject { |_, found| found.empty? }.map do |kind, found|
          "geometry #{kind}: #{surface} #{found.size} computed value(s) off the tokens - #{found.uniq.first(4).join('; ')} law=#{LAWS.fetch(kind)}"
        end
      end

      def on_spacing?(px, tokens) = (px.abs % 4) < 0.05 || Array(tokens[:space_px]).any? { |step| (step - px.abs).abs < 0.05 }

      def off_spacing(el, tokens)
        Array(el["spacing"]).zip(SIDES).filter_map { |px, side| "#{el['key']} #{side} #{px}px" if px && !on_spacing?(px, tokens) }
      end

      def off_leading(el, tokens)
        size = el["font_size"].to_f
        leading = el["line_height"].to_f
        return if size <= 0 || leading <= 0 || el["text"].to_s.strip.empty?

        ratio = leading / size
        return if Array(tokens[:line_height]).any? { |step| (step - ratio).abs < 0.02 }

        "#{el['key']} line-height #{leading}px on #{size}px (#{ratio.round(2)})"
      end

      # Half the box or more is a circle or a pill: a shape, not a step.
      def off_radius(el, tokens)
        half = (el["frect"] || {}).values_at("w", "h").map(&:to_f).min.to_f / 2
        odd = el["border_radius"].to_s.scan(/(-?[\d.]+)px/).flatten.map(&:to_f)
                .reject { |px| px >= half - 0.5 || Array(tokens[:radius_px]).include?(px) }
        "#{el['key']} border-radius #{odd.first}px" if odd.any?
      end

      def off_palette(el, tokens)
        hex = el["bg"].to_s.downcase
        "#{el['key']} bg #{hex}" if hex.start_with?("#") && !palette(tokens).include?(hex)
      end

      def fractional(el)
        size = el["font_size"].to_f
        "#{el['key']} font-size #{size}px" if size.positive? && (size % 1).abs > 0.05 && !el["text"].to_s.strip.empty?
      end

      def type_scale(shown, tokens)
        limit = tokens.fetch(:max_font_sizes, 8)
        sizes = shown.filter_map { |el| el["font_size"].to_f unless el["text"].to_s.strip.empty? }.uniq.sort
        sizes.size > limit ? ["#{sizes.size} distinct font sizes over #{limit} (#{sizes.join(', ')}px)"] : []
      end

      def palette(tokens) = (%w[#000000 #ffffff] + Array(tokens[:palette]).map { |hex| expand(hex) }).uniq

      def expand(hex)
        digits = hex.to_s.downcase.delete_prefix("#")
        "##{digits.size <= 4 ? digits.chars.map { |d| d * 2 }.join[0, 6] : digits[0, 6]}"
      end

      # Negative space, grouping and type detail on the first screen (the
      # operator's 2026-11-06 directives), plus one line of counts the
      # ratchets hold: elements, colours, shadows, left edges, empty share.
      def space(surface, height:, width:, elements:)
        leaves = Array(elements).select do |el|
          el["visible"] && el["frect"] && !el["text"].to_s.strip.empty? && el["frect"]["y"].to_f < height
        end
        return [] if leaves.empty?

        found = {
          "heading_proximity" => [proximity(leaves), "NEGATIVE_SPACE_GROUPING"],
          "heading_wrap" => [wraps(leaves), "HEADING_WRAP_BALANCE"],
          "body_sizes" => [body_sizes(leaves), "TYPE_HIERARCHY"],
          "edge_crowding" => [crowding(leaves, width), "WHITESPACE_RHYTHM"],
          "void" => [voids(leaves, height), "NEGATIVE_SPACE_GROUPING"]
        }
        found.reject { |_, (rows, _)| rows.empty? }.map { |kind, (rows, law)| "geometry #{kind}: #{surface} #{rows.first(4).join('; ')} law=#{law}" } +
          ["geometry minimalism: #{surface} #{counts(leaves, height, width)} law=AESTHETIC_MINIMALISM"]
      end

      def proximity(leaves)
        leaves.select { |el| el["tag"].to_s.match?(HEADING) }.filter_map do |heading|
          above = gap(heading, leaves, :above)
          below = gap(heading, leaves, :below)
          "#{heading['key']} sits #{above.round}px under the block above and #{below.round}px over its text" if above && below && above < below
        end
      end

      def gap(el, leaves, side)
        box = el["frect"]
        leaves.filter_map do |other|
          rect = other["frect"]
          next if other.equal?(el) || !(box["x"] < rect["x"] + rect["w"] && rect["x"] < box["x"] + box["w"])

          distance = side == :above ? box["y"] - bottom(rect) : rect["y"] - bottom(box)
          distance if distance >= 0
        end.min
      end

      def bottom(rect) = rect["y"].to_f + rect["h"].to_f

      def wraps(leaves)
        leaves.filter_map do |el|
          next unless el["tag"].to_s.match?(/\Ah[1-3]\z/) && el["text_lines"].to_i >= 2 && !el["text_wrap"].to_s.match?(/balance|pretty/)

          "#{el['key']} breaks onto #{el['text_lines']} lines with text-wrap #{el['text_wrap'] || 'wrap'}"
        end
      end

      def body_sizes(leaves)
        sizes = leaves.reject { |el| el["tag"].to_s.match?(HEADING) }.map { |el| el["font_size"].to_f }.uniq.sort
        sizes.size > BODY_SIZES_MAX ? ["#{sizes.size} body-side sizes over #{BODY_SIZES_MAX} (#{sizes.join(', ')}px)"] : []
      end

      def crowding(leaves, width)
        return [] if width > 767

        leaves.filter_map do |el|
          rect = el["frect"]
          next if rect["w"].to_f >= width - 1

          margin = [rect["x"].to_f, width - rect["x"].to_f - rect["w"].to_f].min
          "#{el['key']} #{margin.round}px from the edge" if margin < EDGE_FLOOR
        end
      end

      def voids(leaves, height)
        spans = leaves.map { |el| [el["frect"]["y"].to_f, bottom(el["frect"])] }.sort
        reach = spans.first.last
        spans.drop(1).filter_map do |top, low|
          empty = top - reach
          reach = [reach, low].max
          "#{empty.round}px empty band above y=#{top.round}" if empty > height * VOID_SHARE
        end
      end

      def counts(leaves, height, width)
        rects = leaves.map { |el| el["frect"] }
        painted = rects.sum { |r| r["w"].to_f * r["h"].to_f }
        empty = (100 - [painted / (width * height.to_f) * 100, 100].min).round
        "elements=#{leaves.size} colours=#{leaves.flat_map { |el| [el['color'], el['bg']] }.compact.uniq.size} " \
          "shadows=#{leaves.count { |el| el['box_shadow'] }} left_edges=#{rects.map { |r| r['x'].to_f.round }.uniq.size} empty=#{empty}%"
      end
    end

    # The token-value ratchets (pub4 c5c44bb599): Wallace's census of the
    # distinct values each design property takes in a compiled stylesheet,
    # and a literal colour in a colour property that the tokens do not declare
    # (stylelint-declaration-strict-value's rule).
    module Census
      PROPS = %w[font-size line-height font-weight letter-spacing color background-color border-color border-radius
                 padding margin gap box-shadow z-index].freeze
      DECLARATION = /(?<![-\w])(?<prop>[a-z-]+)\s*:\s*(?<value>[^;{}]+)/
      COLOR_PROPS = %w[color background background-color border border-top border-right border-bottom border-left
                       border-color outline outline-color fill stroke caret-color text-decoration-color accent-color].freeze
      LITERAL = /#\h{3,8}\b|rgba?\([^)]*\)/

      module_function

      def counts(css)
        seen = Hash.new { |h, k| h[k] = {} }
        css.gsub(%r{/\*.*?\*/}m, " ").scan(DECLARATION) do
          seen[Regexp.last_match[:prop]][Regexp.last_match[:value].sub("!important", "").strip.downcase.squeeze(" ")] = true
        end
        PROPS.to_h { |prop| [prop, seen[prop].size] }
      end

      # [property, count, baseline] for each count over its baseline.
      def over(css, baselines) = counts(css).filter_map { |prop, n| [prop, n, baselines[prop]] if baselines[prop] && n > baselines[prop] }

      def off_token_colors(css, palette)
        known = palette.map { |hex| Audit.expand(hex) }
        css.scan(DECLARATION).flat_map do |prop, value|
          next [] unless COLOR_PROPS.include?(prop)

          value.scan(LITERAL).reject { |literal| (hex = hex_of(literal)).nil? || known.include?(hex) }
        end
      end

      def hex_of(literal)
        return Audit.expand(literal) if literal.start_with?("#")

        channels = literal.scan(/[\d.]+/).first(3).map { |part| part.to_f.round.clamp(0, 255) }
        format("#%02x%02x%02x", *channels) if channels.size == 3
      end
    end
  end
end
