# frozen_string_literal: true

require "zlib"

module Deploy
  # Small, dependency-free PNG comparator for screenshots produced by Chromium.
  # Supports the non-interlaced 8-bit RGB/RGBA PNG formats Chrome emits. It
  # deliberately rejects formats it cannot prove correct rather than guessing.
  module PngDiff
    SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
    MAX_PIXELS = 15_000_000
    InvalidPng = Class.new(StandardError)

    module_function

    def compare(baseline_path:, current_path:, diff_path: nil)
      baseline = decode(File.binread(baseline_path))
      current = decode(File.binread(current_path))

      unless baseline[:width] == current[:width] && baseline[:height] == current[:height]
        return {
          status: :dimension_mismatch,
          baseline_dimensions: [baseline[:width], baseline[:height]],
          current_dimensions: [current[:width], current[:height]],
          pixel_diff_count: nil,
          pixel_diff_ratio: nil,
          pixel_diff_image: nil,
        }
      end

      width = current[:width]
      height = current[:height]
      base_channels = baseline[:channels]
      current_channels = current[:channels]
      base_row_bytes = width * base_channels

      current_row_bytes = width * current_channels
      base_previous = Array.new(base_row_bytes, 0)
      current_previous = Array.new(current_row_bytes, 0)
      heatmap = String.new(encoding: Encoding::BINARY)
      changed = 0

      height.times do |y|
        base_scanline = baseline[:raw].byteslice(y * (base_row_bytes + 1), base_row_bytes + 1)
        current_scanline = current[:raw].byteslice(y * (current_row_bytes + 1), current_row_bytes + 1)
        base_row = unfilter(base_scanline.getbyte(0), base_scanline.byteslice(1, base_row_bytes), base_previous, base_channels)
        current_row = unfilter(current_scanline.getbyte(0), current_scanline.byteslice(1, current_row_bytes), current_previous, current_channels)
        pixel_row = String.new(capacity: width * 4, encoding: Encoding::BINARY)

        width.times do |x|
          bi = x * base_channels
          ci = x * current_channels
          same = base_row[bi] == current_row[ci] &&
                 base_row[bi + 1] == current_row[ci + 1] &&
                 base_row[bi + 2] == current_row[ci + 2]

          if base_channels == 4 || current_channels == 4
            base_alpha = base_channels == 4 ? base_row[bi + 3] : 255
            current_alpha = current_channels == 4 ? current_row[ci + 3] : 255
            same &&= base_alpha == current_alpha
          end

          if same
            pixel_row << 0 << 0 << 0 << 0
          else
            changed += 1
            pixel_row << 255 << 0 << 64 << 255
          end
        end

        heatmap << pixel_row
        base_previous = base_row
        current_previous = current_row
      end

      ratio = changed.to_f / (width * height)
      image_path = nil
      if changed.positive? && diff_path
        File.binwrite(diff_path, encode_rgba(width, height, heatmap))
        image_path = diff_path
      end

      {
        status: :compared,
        width:,
        height:,
        pixel_diff_count: changed,
        pixel_diff_ratio: ratio.round(8),
        pixel_diff_image: image_path,
      }
    rescue Errno::ENOENT, Errno::EACCES
      raise
    rescue InvalidPng
      raise
    rescue Zlib::Error, NoMethodError, TypeError, ArgumentError => e
      raise InvalidPng, "invalid PNG data: #{e.class}: #{e.message}"
    end

    # A coarse, resize-invariant view of an image: FINGERPRINT_CELLS squared
    # box-sampled grayscale cells on the 0-255 scale. Two captures of the same
    # state land within a cell or two of each other; two different pages do not.
    # Byte comparison cannot see that -- a single anti-aliased glyph or a stray
    # count is a different file with the same surface underneath, and a review
    # that shows both reads as an overlap.
    FINGERPRINT_CELLS = 32
    # Per-cell mean absolute difference under which two fingerprints are the
    # same surface. Measured on the 2026-11-13 review set: same-state captures
    # sit at <= 0.02, different pages at >= 4.3, so 1.0 separates them with an
    # order of magnitude of margin on both sides.
    FINGERPRINT_TOLERANCE = 1.0

    # One fingerprint: its dimensions and its cells. Two fingerprints compare
    # equal only when the dimensions agree, so a short and a tall capture of the
    # same route never collapse into one slide.
    Fingerprint = Data.define(:width, :height, :grid) do
      def distance(other)
        return Float::INFINITY unless width == other.width && height == other.height

        grid.each_with_index.sum { |cell, index| (cell - other.grid[index]).abs }.to_f / grid.size
      end

      def similar?(other, tolerance: PngDiff::FINGERPRINT_TOLERANCE)
        distance(other) <= tolerance
      end
    end

    # The fingerprint of a PNG's bytes. Raises InvalidPng for a format the
    # decoder will not guess at, so a caller decides whether to skip or fail.
    def fingerprint(bytes)
      image = decode(bytes)
      width = image[:width]
      height = image[:height]
      channels = image[:channels]
      cells = FINGERPRINT_CELLS
      grid = Array.new(cells * cells, 0)
      previous = Array.new(width * channels, 0)

      cells.times do |cell_row|
        first_row = cell_row * height / cells
        last_row = [((cell_row + 1) * height / cells) - 1, first_row].max
        row = nil
        first_row.upto(last_row) do |y|
          scanline = image[:raw].byteslice(y * (width * channels + 1), width * channels + 1)
          row = unfilter_row(scanline, previous:, channels:)
          previous = row
        end

        cells.times do |cell_column|
          first_column = cell_column * width / cells
          last_column = [((cell_column + 1) * width / cells) - 1, first_column].max
          total = 0
          count = 0
          first_column.upto(last_column) do |x|
            index = x * channels
            total += (row[index] * 299 + row[index + 1] * 587 + row[index + 2] * 114) / 1000
            count += 1
          end
          grid[cell_row * cells + cell_column] = count.zero? ? 0 : total / count
        end
      end

      Fingerprint.new(width:, height:, grid:)
    end

    # Used by the comparator for its red/transparent overlay and by tiny unit
    # fixtures. Input is packed RGBA pixels, four bytes per pixel, row-major.
    def encode_rgba(width, height, rgba)
      unless width.to_i.positive? && height.to_i.positive? &&
             width * height <= MAX_PIXELS && rgba.bytesize == width * height * 4
        raise ArgumentError, "RGBA dimensions and bytes do not agree"
      end

      raw = String.new(encoding: Encoding::BINARY)
      row_bytes = width * 4
      height.times do |y|
        raw << 0
        raw << rgba.byteslice(y * row_bytes, row_bytes)
      end
      SIGNATURE + chunk("IHDR", [width, height, 8, 6, 0, 0, 0].pack("NNCCCCC")) +
        chunk("IDAT", Zlib::Deflate.deflate(raw)) + chunk("IEND", "".b)
    end

    def decode(bytes)
      raise InvalidPng, "missing PNG signature" unless bytes.start_with?(SIGNATURE)

      offset = SIGNATURE.bytesize
      header = nil
      compressed = String.new(encoding: Encoding::BINARY)
      ended = false

      while offset + 12 <= bytes.bytesize
        length = bytes.byteslice(offset, 4).unpack1("N")
        type = bytes.byteslice(offset + 4, 4)
        data_start = offset + 8
        data_end = data_start + length
        raise InvalidPng, "truncated PNG chunk" if data_end + 4 > bytes.bytesize

        data = bytes.byteslice(data_start, length)
        crc = bytes.byteslice(data_end, 4).unpack1("N")
        raise InvalidPng, "PNG CRC mismatch in #{type}" unless Zlib.crc32(type + data) == crc

        case type
        when "IHDR"
          raise InvalidPng, "duplicate PNG header" if header
          raise InvalidPng, "bad PNG header length" unless data.bytesize == 13
          header = data.unpack("NNCCCCC")
        when "IDAT"
          raise InvalidPng, "PNG data precedes header" unless header

          compressed << data
        when "IEND"
          ended = true
          break
        end
        offset = data_end + 4
      end

      raise InvalidPng, "incomplete PNG" unless header && ended
      width, height, bit_depth, color_type, compression, filter_method, interlace = header
      raise InvalidPng, "invalid PNG dimensions" unless width.positive? && height.positive? && width * height <= MAX_PIXELS
      raise InvalidPng, "only 8-bit RGB/RGBA PNG is supported" unless bit_depth == 8 && [2, 6].include?(color_type)
      raise InvalidPng, "unsupported PNG compression/filter/interlace" unless compression.zero? && filter_method.zero? && interlace.zero?

      channels = color_type == 6 ? 4 : 3
      expected = height * (width * channels + 1)
      raw = Zlib::Inflate.inflate(compressed)
      raise InvalidPng, "PNG scanline length mismatch" unless raw.bytesize == expected

      { width:, height:, channels:, raw: }
    end

    # One scanline as stored (filter byte first) back to its bytes, for a reader that walks pixels.
    def unfilter_row(scanline, previous:, channels:)
      unfilter(scanline.getbyte(0), scanline.byteslice(1, scanline.bytesize - 1), previous, channels)
    end

    def unfilter(filter, bytes, previous, bytes_per_pixel)
      raise InvalidPng, "unknown PNG row filter #{filter}" unless (0..4).cover?(filter)

      row = Array.new(bytes.bytesize, 0)
      bytes.bytesize.times do |i|
        value = bytes.getbyte(i)
        left = i >= bytes_per_pixel ? row[i - bytes_per_pixel] : 0
        above = previous[i] || 0
        upper_left = i >= bytes_per_pixel ? (previous[i - bytes_per_pixel] || 0) : 0

        predictor = case filter
                    when 0 then 0
                    when 1 then left
                    when 2 then above
                    when 3 then (left + above) / 2
                    when 4 then paeth(left, above, upper_left)
                    end

        row[i] = (value + predictor) & 0xff
      end
      row
    end

    def paeth(left, above, upper_left)
      p = left + above - upper_left
      distances = [(p - left).abs, (p - above).abs, (p - upper_left).abs]
      return left if distances[0] <= distances[1] && distances[0] <= distances[2]
      return above if distances[1] <= distances[2]

      upper_left
    end

    def chunk(type, data)
      type_bytes = type.b
      data_bytes = data.b
      [data_bytes.bytesize].pack("N") + type_bytes + data_bytes +
        [Zlib.crc32(type_bytes + data_bytes)].pack("N")
    end
    private_class_method :unfilter, :paeth, :chunk
  end
end
