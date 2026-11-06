# frozen_string_literal: true

require "zlib"

module Fix
  module Visual
    # The PNG reader and writer the pixel diff stands on, moved from pub4
    # MASTER/checks/support/png_diff.rb: the non-interlaced 8-bit RGB and
    # RGBA PNGs Chromium writes, nothing it cannot prove it read right.
    # Bytes in, bytes out; the caller writes through World.
    module Png
      SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
      MAX_PIXELS = 15_000_000
      Invalid = Class.new(StandardError)

      module_function

      # Packed RGBA bytes, four a pixel, row-major, as a PNG.
      def encode(width, height, rgba)
        unless width.positive? && height.positive? && width * height <= MAX_PIXELS && rgba.bytesize == width * height * 4
          raise ArgumentError, "RGBA dimensions and bytes do not agree"
        end

        row = width * 4
        raw = String.new(encoding: Encoding::BINARY)
        height.times { |y| raw << 0 << rgba.byteslice(y * row, row) }
        SIGNATURE + chunk("IHDR", [width, height, 8, 6, 0, 0, 0].pack("NNCCCCC")) +
          chunk("IDAT", Zlib::Deflate.deflate(raw)) + chunk("IEND", "".b)
      end

      # { width:, height:, channels:, raw: } with raw still row-filtered.
      def decode(bytes)
        bytes = bytes.b
        raise Invalid, "missing PNG signature" unless bytes.start_with?(SIGNATURE)

        header, compressed = chunks(bytes)
        width, height, depth, color, compression, filter, interlace = header
        raise Invalid, "invalid PNG dimensions" unless width.positive? && height.positive? && width * height <= MAX_PIXELS
        raise Invalid, "only 8-bit RGB/RGBA PNG is supported" unless depth == 8 && [2, 6].include?(color)
        raise Invalid, "unsupported compression, filter or interlace" unless [compression, filter, interlace].all?(&:zero?)

        channels = color == 6 ? 4 : 3
        raw = Zlib::Inflate.inflate(compressed)
        raise Invalid, "PNG scanline length mismatch" unless raw.bytesize == height * (width * channels + 1)

        { width:, height:, channels:, raw: }
      rescue Zlib::Error => e
        raise Invalid, "invalid PNG data: #{e.message}"
      end

      def chunks(bytes)
        offset = SIGNATURE.bytesize
        header = nil
        compressed = String.new(encoding: Encoding::BINARY)
        while offset + 12 <= bytes.bytesize
          length = bytes.byteslice(offset, 4).unpack1("N")
          type = bytes.byteslice(offset + 4, 4)
          data = bytes.byteslice(offset + 8, length)
          raise Invalid, "truncated PNG chunk" if offset + 12 + length > bytes.bytesize
          raise Invalid, "PNG CRC mismatch in #{type}" unless Zlib.crc32(type + data) == bytes.byteslice(offset + 8 + length, 4).unpack1("N")

          case type
          when "IHDR" then header = data.unpack("NNCCCCC")
          when "IDAT" then compressed << data
          when "IEND" then return [header || raise(Invalid, "no PNG header"), compressed]
          end
          offset += 12 + length
        end
        raise Invalid, "incomplete PNG"
      end

      # One stored scanline (filter byte first) back to its bytes.
      def unfilter(scanline, previous, channels)
        filter = scanline.getbyte(0)
        raise Invalid, "unknown PNG row filter #{filter}" unless (0..4).cover?(filter)

        row = Array.new(scanline.bytesize - 1, 0)
        row.size.times do |i|
          left = i >= channels ? row[i - channels] : 0
          above = previous[i] || 0
          corner = i >= channels ? previous[i - channels] || 0 : 0
          predictor = [0, left, above, (left + above) / 2, paeth(left, above, corner)][filter]
          row[i] = (scanline.getbyte(i + 1) + predictor) & 0xff
        end
        row
      end

      def paeth(left, above, corner)
        estimate = left + above - corner
        distances = [left, above, corner].map { |v| (estimate - v).abs }
        return left if distances[0] <= distances[1] && distances[0] <= distances[2]

        distances[1] <= distances[2] ? above : corner
      end

      def chunk(type, data) = [data.bytesize].pack("N") + type.b + data.b + [Zlib.crc32(type.b + data.b)].pack("N")
    end
  end
end
