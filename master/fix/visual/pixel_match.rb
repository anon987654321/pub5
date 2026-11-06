# frozen_string_literal: true

require_relative "png"

module Fix
  module Visual
    # pixelmatch (mapbox/pixelmatch, ISC) in Ruby, moved from pub4
    # MASTER/checks/support/pixel_match.rb (5745846704). A byte that moved is
    # not a change: the colour delta is perceptual (YIQ, threshold 0.1), and a
    # pixel between a darker and a lighter neighbour that both sit in flat
    # areas, in both images, is an edge resampled. Changed pixels come back as
    # boxes on a 16px grid, with a diff image and a 4x crop of any box for the
    # reviewer.
    module PixelMatch
      THRESHOLD = 0.1
      MAX_YIQ = 35_215.0
      CELL = 16
      ZOOM = 4
      Y = [0.29889531, 0.58662247, 0.11448223].freeze
      I = [0.59597799, -0.2741761, -0.32180189].freeze
      Q = [0.21147017, -0.52261711, 0.31114694].freeze

      Frame = Data.define(:width, :height, :pixels) do
        def at(col, row) = pixels[row * width + col]
        def edge?(col, row) = col.zero? || row.zero? || col == width - 1 || row == height - 1
        def place(pos) = pos.divmod(width).reverse
        def size = [width, height]
        def lines = pixels.each_slice(width).to_a

        def neighbours(col, row)
          rows = ([row - 1, 0].max..[row + 1, height - 1].min).to_a
          cols = ([col - 1, 0].max..[col + 1, width - 1].min).to_a
          rows.product(cols).map(&:reverse) - [[col, row]]
        end
      end

      module_function

      def read(bytes)
        decoded = Png.decode(bytes)
        channels = decoded[:channels]
        row_bytes = decoded[:width] * channels
        previous = Array.new(row_bytes, 0)
        rows = Array.new(decoded[:height]) do |line|
          previous = Png.unfilter(decoded[:raw].byteslice(line * (row_bytes + 1), row_bytes + 1), previous, channels)
          channels == 4 ? previous.pack("C*").unpack("N*") : previous.each_slice(3).map { |r, g, b| (r << 24) | (g << 16) | (b << 8) | 255 }
        end
        Frame.new(width: decoded[:width], height: decoded[:height], pixels: rows.flatten)
      end

      def pack(rgba) = rgba.inject(0) { |word, channel| (word << 8) | channel }

      def unpack(word) = [24, 16, 8, 0].map { |shift| (word >> shift) & 255 }

      def frame_png(frame) = Png.encode(frame.width, frame.height, frame.pixels.pack("N*"))

      # baseline vs current PNG bytes: changed and anti-aliased counts, the
      # changed boxes and a diff PNG (changed red, aliased yellow, the rest a
      # faded baseline) when anything changed.
      def compare(baseline, current, threshold: THRESHOLD)
        base = read(baseline)
        now = read(current)
        return { status: :dimension_mismatch, sizes: [base.size, now.size], pixel_diff_count: nil, regions: [] } unless base.size == now.size

        mask = scan(base, now, MAX_YIQ * threshold * threshold)
        changed = mask.count { |_, kind| kind == :diff }
        { status: :compared, width: base.width, height: base.height, pixel_diff_count: changed,
          aliased: mask.size - changed, pixel_diff_ratio: (changed.to_f / base.pixels.size).round(8),
          regions: regions(mask, base), diff_png: changed.positive? ? diff_png(base, mask) : nil }
      end

      def scan(base, now, max_delta)
        base.pixels.each_index.with_object({}) do |pos, mask|
          one = base.pixels[pos]
          two = now.pixels[pos]
          next if one == two || delta(one, two).abs <= max_delta

          place = base.place(pos)
          mask[pos] = antialiased?(base, now, place) || antialiased?(now, base, place) ? :aliased : :diff
        end
      end

      def delta(first, second)
        y, i, q = yiq_all(blend(first)).zip(yiq_all(blend(second))).map { |a, b| a - b }
        value = (0.5053 * (y**2)) + (0.299 * (i**2)) + (0.1957 * (q**2))
        y.positive? ? -value : value
      end

      def yiq_all(rgb) = [Y, I, Q].map { |weights| yiq(rgb, weights) }

      def yiq(rgb, weights) = (rgb[0] * weights[0]) + (rgb[1] * weights[1]) + (rgb[2] * weights[2])

      def luma(word) = yiq(blend(word), Y)

      # Translucent pixels are read over white, as pixelmatch does.
      def blend(word)
        *rgb, alpha = unpack(word)
        alpha == 255 ? rgb : rgb.map { |c| 255 + ((c - 255) * alpha / 255.0) }
      end

      def antialiased?(frame, other, place)
        centre = luma(frame.at(*place))
        steps = frame.neighbours(*place).map { |spot| [centre - luma(frame.at(*spot)), spot] }
        return false if steps.count { |step, _| step.zero? } + (frame.edge?(*place) ? 1 : 0) > 2

        low, high = steps.minmax_by(&:first)
        return false unless low.first.negative? && high.first.positive?

        [low.last, high.last].any? { |spot| flat?(frame, spot) && flat?(other, spot) }
      end

      def flat?(frame, spot)
        centre = frame.at(*spot)
        frame.neighbours(*spot).count { |near| frame.at(*near) == centre } + (frame.edge?(*spot) ? 1 : 0) > 2
      end

      def regions(mask, frame)
        pending = mask.select { |_, kind| kind == :diff }.keys.map { |pos| frame.place(pos).map { |at| at / CELL } }.uniq
                      .to_h { |cell| [cell, true] }
        boxes = []
        boxes << box(flood(pending, pending.keys.first), frame) until pending.empty?
        boxes.sort_by { |found| [found[:y], found[:x]] }
      end

      def flood(pending, start)
        stack = [start]
        group = []
        pending.delete(start)
        while (spot = stack.pop)
          group << spot
          [-1, 0, 1].product([-1, 0, 1]).each do |dc, dr|
            near = [spot[0] + dc, spot[1] + dr]
            stack << near if pending.delete(near)
          end
        end
        group
      end

      def box(group, frame)
        cols, rows = group.transpose
        left = cols.min * CELL
        top = rows.min * CELL
        { x: left, y: top, w: [(cols.max + 1) * CELL, frame.width].min - left, h: [(rows.max + 1) * CELL, frame.height].min - top }
      end

      def diff_png(base, mask)
        red = pack([255, 0, 0, 255])
        yellow = pack([255, 255, 0, 255])
        pixels = base.pixels.each_with_index.map do |word, pos|
          case mask[pos]
          when :diff then red
          when :aliased then yellow
          else
            grey = (255 + ((luma(word) - 255) * 0.1)).round
            pack([grey, grey, grey, 255])
          end
        end
        Png.encode(base.width, base.height, pixels.pack("N*"))
      end

      # A box of the image, padded and enlarged ZOOM times by nearest
      # neighbour, so an edge or a baseline is judged at the pixel.
      def crop(bytes, area, pad: 8)
        frame = read(bytes)
        left = (area[:x] - pad).clamp(0, frame.width - 1)
        top = (area[:y] - pad).clamp(0, frame.height - 1)
        width = [area[:w] + (2 * pad), frame.width - left].min
        height = [area[:h] + (2 * pad), frame.height - top].min
        rows = Array.new(height * ZOOM) { |line| Array.new(width * ZOOM) { |col| frame.at(left + (col / ZOOM), top + (line / ZOOM)) } }
        Png.encode(width * ZOOM, height * ZOOM, rows.flatten.pack("N*"))
      end
    end
  end
end
