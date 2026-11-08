# frozen_string_literal: true

require "optparse"

module Master
  module Visual
    # Contact sheets and labelled 1:1 crops for the screenshot review, on the
    # tree's own libvips stack (ruby-vips, MASTER/Gemfile). This is the Ruby
    # port of the retired scripts/analysis helpers: the same operation
    # sequence the 2026-11-06 review sheets were cut with, without their
    # hardcoded capture paths and crop lists - those belonged to one review
    # pass over captures the register has since ordered recaptured.
    #
    #   ruby MASTER/tools/visual/sheets.rb sheet out.jpg --columns 3 --width 730 img1.png img2.png
    #   ruby MASTER/tools/visual/sheets.rb crop out.jpg img.png 0,18,900,64 --label "nav strip"
    #
    # Every tile is captioned with its file name (or the given label); a
    # caption that cannot render degrades to an unlabelled tile with a note
    # on stderr, never to a missing tile.
    module Sheets
      GAP = 14
      BG = 235
      SHEET_QUALITY = 82
      CROP_QUALITY = 85
      LABEL_FONT = "DejaVu Sans 20"
      CROP_LABEL_FONT = "DejaVu Sans 22"

      USAGE = <<~TEXT
        usage: sheets.rb sheet <out.jpg> [--columns N] [--width N] [--root DIR] IMG...
               sheets.rb crop <out.jpg> <IMG> LEFT,TOP,WIDTH,HEIGHT [--scale F] [--label TEXT] [--root DIR]
      TEXT

      module_function

      # "left,top,width,height" into the four integers libvips extracts with.
      # Raises ArgumentError on anything else: a silent clamp would review the
      # wrong pixels.
      def parse_crop(text)
        parts = text.split(",", -1).map { |piece| Integer(piece, 10) }
        raise ArgumentError, "crop needs left,top,width,height: #{text.inspect}" unless parts.size == 4
        raise ArgumentError, "crop origin must not be negative: #{text.inspect}" if parts[0].negative? || parts[1].negative?
        raise ArgumentError, "crop width and height must be positive: #{text.inspect}" if parts[2] < 1 || parts[3] < 1

        parts
      end

      def rows(tiles, columns:)
        raise ArgumentError, "columns must be positive: #{columns.inspect}" unless columns.to_i.positive?

        tiles.each_slice(columns.to_i).to_a
      end

      def scale_for(target_width, source_width)
        raise ArgumentError, "source image has no width" unless source_width.to_i.positive?
        raise ArgumentError, "target width must be positive: #{target_width.inspect}" unless target_width.to_i.positive?

        target_width.to_f / source_width
      end

      def label_for(path)
        File.basename(path.to_s).sub(/\.(?:png|jpg|jpeg)\z/i, "")
      end

      def cli(argv)
        command = argv.shift
        raise ArgumentError, USAGE.strip unless %w[sheet crop].include?(command)

        require "vips"
        public_send(command == "sheet" ? :run_sheet : :run_crop, argv)
        nil
      rescue OptionParser::ParseError, ArgumentError => e
        warn "sheets: #{e.message}"
        warn USAGE
        raise
      end

      def run_sheet(argv)
        options = { columns: 3, width: 730, root: "." }
        parser = OptionParser.new do |o|
          o.on("--columns N", Integer) { |value| options[:columns] = value }
          o.on("--width N", Integer) { |value| options[:width] = value }
          o.on("--root DIR") { |value| options[:root] = value }
        end
        positionals = parser.parse(argv)
        out = positionals.shift
        images = positionals
        raise ArgumentError, "sheet needs an output path and at least one image" if out.to_s.empty? || images.empty?

        tiles = images.map { |path| labelled_tile(File.expand_path(path, options[:root]), options[:width]) }
        composed = stack(rows(tiles, columns: options[:columns]))
        save(composed, File.expand_path(out, options[:root]), SHEET_QUALITY)
      end

      def run_crop(argv)
        options = { scale: 1.0, label: nil, root: "." }
        parser = OptionParser.new do |o|
          o.on("--scale F", Float) { |value| options[:scale] = value }
          o.on("--label TEXT") { |value| options[:label] = value }
          o.on("--root DIR") { |value| options[:root] = value }
        end
        positionals = parser.parse(argv)
        out = positionals.shift
        source = positionals.shift
        crop_text = positionals.shift
        raise ArgumentError, "crop needs an output, an image and LEFT,TOP,WIDTH,HEIGHT" if crop_text.to_s.empty?

        image = Vips::Image.new_from_file(File.expand_path(source, options[:root]), access: :random)
        left, top, width, height = parse_crop(crop_text)
        save(labelled_crop(image, options[:label] || label_for(source), crop: [left, top, width, height],
                                                        scale: options[:scale]),
             File.expand_path(out, options[:root]), CROP_QUALITY)
      end

      # Thumbnail to width and prepend a caption strip.
      def labelled_tile(path, width)
        source = Vips::Image.new_from_file(path, access: :sequential)
        caption_strip(source.resize(scale_for(width, source.width)), label_for(path), LABEL_FONT, width)
      end

      def labelled_crop(image, label, crop:, scale: 1.0)
        piece = image.crop(*crop)
        piece = piece.resize(scale) unless scale == 1.0
        caption_strip(piece, label, CROP_LABEL_FONT, piece.width)
      end

      # The caption is tried and named when it fails: a sheet without labels
      # lies about what it shows more quietly than a warning does.
      def caption_strip(image, text, font, width)
        caption = Vips::Image.text(text, font: font, dpi: 72, width: width, align: :centre)
        strip = caption.embed(-1, -3, width, caption.height + 4, background: BG)
        strip.join(image, :vertical, expand: true, background: BG)
      rescue Vips::Error => e
        warn "sheets: caption #{text.inspect} did not render (#{e.message}); tile saved without its label"
        image
      end

      def row(tiles)
        height = tiles.map(&:height).max
        tiles.map { |tile| tile.embed(0, 0, tile.width, height, background: BG) }
             .reduce { |left, right| left.join(right, :horizontal, expand: true, background: BG, shim: GAP) }
      end

      def stack(rows_of_tiles)
        width = rows_of_tiles.map { |line| line.map(&:width).max }.max
        rows_of_tiles.map { |line| line.map { |tile| tile.embed(0, 0, width, tile.height, background: BG) } }
                     .reduce { |top, bottom| top.join(bottom, :vertical, expand: true, background: BG, shim: GAP) }
      end

      def save(image, path, quality)
        image.jpegsave(path, Q: quality)
        puts "#{File.basename(path)} #{image.width} x #{image.height}"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Master::Visual::Sheets.cli(ARGV)
  rescue LoadError => e
    warn "sheets: #{e.message}"
    exit 77
  rescue OptionParser::ParseError, ArgumentError
    exit 64
  rescue StandardError => e
    warn "sheets: #{e.message}"
    exit 66
  end
end
