# frozen_string_literal: true

require_relative "png_diff"

module Deploy
  # Composite evidence for a pair of captures. PngDiff answers "how much
  # changed" with a number and a red heatmap; VisualRegister answers "where do
  # the two captures sit relative to each other" with an image a reviewer reads
  # at a glance. Every mode is a pure pixel function over two same-size PNGs,
  # so the instrument needs no browser and no gems beyond PngDiff's own zlib.
  #
  #   difference    |A-B| per channel, amplified. Identical pixels are black;
  #                 drift lights up. Amplification makes sub-perceptual drift
  #                 visible; the count and ratio still come from PngDiff.
  #   anaglyph      A into the red channel, B into green+blue. Registered
  #                 pixels read gray; drift shows as red/cyan fringes whose
  #                 direction tells you which way B moved.
  #   overlay       50/50 blend. Double edges mark misalignment - the onion
  #                 skin. Fast to read, not measurable; pair with a ratio.
  #   checkerboard  Alternating tiles of A and B. No blending, so tonal drift
  #                 (one surface token off from another) stays visible.
  #
  # grid_overlay is the one-capture cousin: the rhythm grid laid over a single
  # capture so off-rhythm edges read as lines floating between grid lines.
  module VisualRegister
    MODES = %w[difference anaglyph overlay checkerboard].freeze
    MAX_PIXELS = PngDiff::MAX_PIXELS
    DEFAULT_AMPLIFY = 4
    DEFAULT_TILE = 32
    # The grid reads as an instrument, not as content: hairlines at ~15%
    # strength, every eighth line doubled so the 32px cadence is countable.
    GRID_MINOR_ALPHA = 38
    GRID_MAJOR_ALPHA = 76
    GRID_COLOR = [0, 255, 255].freeze

    module_function

    def composite(a_path:, b_path:, mode:, out_path:, amplify: DEFAULT_AMPLIFY, tile: DEFAULT_TILE)
      raise ArgumentError, "unknown mode #{mode.inspect} (expected one of #{MODES.join(', ')})" unless MODES.include?(mode.to_s)

      a = PngDiff.decode(File.binread(a_path))
      b = PngDiff.decode(File.binread(b_path))
      unless a[:width] == b[:width] && a[:height] == b[:height]
        return {
          status: :dimension_mismatch,
          a_dimensions: [a[:width], a[:height]],
          b_dimensions: [b[:width], b[:height]],
          composite_image: nil,
        }
      end

      rgba = map_rows(a, b) do |a_px, b_px, x, y|
        case mode.to_s
        when "difference"   then difference_pixel(a_px, b_px, amplify)
        when "anaglyph"     then [a_px[0], b_px[1], b_px[2], 255]
        when "overlay"      then overlay_pixel(a_px, b_px)
        else                     (x / tile + y / tile).even? ? opaque(a_px) : opaque(b_px)
        end
      end

      File.binwrite(out_path, PngDiff.encode_rgba(a[:width], a[:height], rgba))
      { status: :composited, mode: mode.to_s, width: a[:width], height: a[:height], composite_image: out_path }
    end

    # One capture under the rhythm grid. spacing is the law's unit (4px);
    # every major_every-th line is drawn stronger so the eye can count.
    def grid_overlay(capture_path:, out_path:, spacing: 4, major_every: 8)
      img = PngDiff.decode(File.binread(capture_path))
      a_ch = img[:channels]
      a_row_bytes = img[:width] * a_ch
      previous = Array.new(a_row_bytes, 0)
      rgba = String.new(encoding: Encoding::BINARY)

      img[:height].times do |y|
        scanline = img[:raw].byteslice(y * (a_row_bytes + 1), a_row_bytes + 1)
        row = PngDiff.unfilter_row(scanline, previous: previous, channels: a_ch)
        img[:width].times do |x|
          i = x * a_ch
          line = (x % spacing).zero? || (y % spacing).zero?
          major = (x % (spacing * major_every)).zero? || (y % (spacing * major_every)).zero?
          alpha = line ? (major ? GRID_MAJOR_ALPHA : GRID_MINOR_ALPHA) : 0
          rgba << blend(GRID_COLOR[0], row[i], alpha) << blend(GRID_COLOR[1], row[i + 1], alpha) <<
                  blend(GRID_COLOR[2], row[i + 2], alpha) << 255
        end
        previous = row
      end

      File.binwrite(out_path, PngDiff.encode_rgba(img[:width], img[:height], rgba))
      { status: :gridded, width: img[:width], height: img[:height], spacing:, composite_image: out_path }
    end

    def difference_pixel(a_px, b_px, amplify)
      [
        clamp((a_px[0] - b_px[0]).abs * amplify),
        clamp((a_px[1] - b_px[1]).abs * amplify),
        clamp((a_px[2] - b_px[2]).abs * amplify),
        255,
      ]
    end

    def overlay_pixel(a_px, b_px)
      [(a_px[0] + b_px[0]) / 2, (a_px[1] + b_px[1]) / 2, (a_px[2] + b_px[2]) / 2, 255]
    end

    # Chromium's RGB screenshots carry no alpha byte; pretend 255 so every
    # mode downstream has a four-element pixel to work with.
    def opaque(px) = [px[0], px[1], px[2], 255]

    def clamp(v) = v > 255 ? 255 : v

    def blend(ink, under, alpha) = (ink * alpha + under * (255 - alpha)) / 255

    # Walks both images row by row (unfiltering through PngDiff, never holding
    # more than a scanline per side) and packs the yielded pixels into one
    # RGBA buffer. Rows keep memory flat on full-viewport captures.
    def map_rows(a, b)
      a_ch = a[:channels]
      b_ch = b[:channels]
      a_row_bytes = a[:width] * a_ch
      b_row_bytes = b[:width] * b_ch
      a_prev = Array.new(a_row_bytes, 0)
      b_prev = Array.new(b_row_bytes, 0)
      out = String.new(capacity: a[:width] * a[:height] * 4, encoding: Encoding::BINARY)

      a[:height].times do |y|
        a_line = a[:raw].byteslice(y * (a_row_bytes + 1), a_row_bytes + 1)
        b_line = b[:raw].byteslice(y * (b_row_bytes + 1), b_row_bytes + 1)
        a_row = PngDiff.unfilter_row(a_line, previous: a_prev, channels: a_ch)
        b_row = PngDiff.unfilter_row(b_line, previous: b_prev, channels: b_ch)

        a[:width].times do |x|
          ai = x * a_ch
          bi = x * b_ch
          a_px = [a_row[ai], a_row[ai + 1], a_row[ai + 2]]
          b_px = [b_row[bi], b_row[bi + 1], b_row[bi + 2]]
          out << yield(a_px, b_px, x, y).pack("C4")
        end
        a_prev = a_row
        b_prev = b_row
      end
      out
    end
  end
end
