#!/usr/bin/env ruby
# frozen_string_literal: true

# Contact sheets and 1:1 crops of the committed RAILS screenshots, for a
# screenshot-led review. ruby-vips, the stack STUDIO/postpro and the
# image_processing Gemfiles already use.
#
#   ruby scripts/analysis/review_sheets.rb [sheet ...]   # default: every sheet
#   REVIEW_SHEETS_OUT=/tmp/render/sheets                 # output directory
#
# Sheets are JPEGs outside the tree; run output never enters git.

require "fileutils"
require "vips"

module ReviewSheets
  REVIEW_ROOT = File.expand_path("../..", __dir__)
  OUT = ENV.fetch("REVIEW_SHEETS_OUT", "/tmp/render/sheets")
  GAP = 14
  BG = 235

  def self.shot(app, name) = "RAILS/#{app}/screenshots/#{name}.png"
  def self.mrdamascy(name) = shot("mrdamascy", name)

  # A tile is [path, caption, crop [left, top, width, height] or nil, scale].
  # A sheet lays its tiles out as rows (an array of rows) or as one column.
  def self.tile(path, caption = File.basename(path, ".*"), crop: nil, scale: 1.0) = [path, caption, crop, scale]

  def self.tiles_at(width, paths)
    paths.map { |path| [path, File.basename(path, ".*"), nil, :"width_#{width}"] }
  end

  MRDAMASCY_REST = %w[02-menu-en 04-menu-after-add 07-tracking 08-loyalty-guest 09-about
                      10-login 11-offline 12-vipps-login-mock 13-staff-board 14-orders].freeze

  SHEETS = {
    "s1-desktop-a" => { q: 82, font: 20, align: :centre, rows: [
      tiles_at(730, [shot("brgen", "brgen-desktop"), shot("brgen_maps", "maps-desktop"),
                     shot("brgen_marketplace", "marketplace-desktop")]),
      tiles_at(730, [shot("brgen_messenger", "messenger-desktop"), shot("brgen_radio", "radio-desktop"),
                     shot("bsdports", "bsdports-desktop")])
    ] },
    "s2-desktop-b" => { q: 82, font: 20, align: :centre, rows: [
      tiles_at(730, [shot("brgen_radio", "tv-desktop"), shot("brgen_dating", "dating-desktop"),
                     shot("amber", "amber-desktop")])
    ] },
    "s3-mobile-a" => { q: 82, font: 20, align: :centre, rows: [
      tiles_at(300, [shot("brgen_messenger", "messenger-mobile"), shot("bsdports", "bsdports-mobile"),
                     shot("brgen_radio", "radio-mobile"), shot("brgen_radio", "tv-mobile"),
                     shot("brgen_dating", "dating-mobile"), shot("amber", "amber-mobile")])
    ] },
    "s4-mobile-b-mrdamascy" => { q: 82, font: 20, align: :centre, rows: [
      tiles_at(300, [shot("brgen", "brgen-mobile"), shot("brgen_maps", "maps-mobile"),
                     shot("brgen_marketplace", "marketplace-mobile"), mrdamascy("01-menu"),
                     mrdamascy("03-item-sheet"), mrdamascy("05-cart"), mrdamascy("06-checkout")])
    ] },
    "s5-mrdamascy-rest" => { q: 85, font: 26, align: :low, rows: MRDAMASCY_REST.each_slice(5).map do |names|
      names.map { |name| tile(mrdamascy(name), name, scale: 0.6) }
    end },
    "c1-crops-a" => { q: 85, font: 26, align: :low, column: [
      tile(shot("brgen", "brgen-desktop"), "brgen-desktop: nav strip y=18", crop: [0, 18, 900, 64]),
      tile(shot("brgen_maps", "maps-desktop"), "maps-desktop: nav strip y=18", crop: [0, 18, 900, 64]),
      tile(shot("brgen_radio", "radio-desktop"), "radio-desktop: nav strip y=18", crop: [0, 18, 900, 64]),
      tile(shot("brgen_maps", "maps-mobile"), "maps-mobile: page top", crop: [0, 0, 390, 150]),
      tile(shot("brgen_maps", "maps-mobile"), "maps-mobile: search row", crop: [0, 40, 390, 110]),
      tile(shot("amber", "amber-desktop"), "amber-desktop: header wordmark", crop: [900, 0, 540, 130]),
      tile(shot("amber", "amber-desktop"), "amber-desktop: Bymorgen tile", crop: [940, 1750, 500, 320]),
      tile(shot("amber", "amber-desktop"), "amber-desktop: footer wordmark", crop: [950, 2820, 490, 190]),
      tile(shot("amber", "amber-mobile"), "amber-mobile: nav row", crop: [0, 30, 390, 70]),
      tile(shot("amber", "amber-mobile"), "amber-mobile: Bymorgen tile", crop: [0, 1330, 390, 260])
    ] },
    "c2-crops-b" => { q: 85, font: 26, align: :low, column: [
      tile(shot("brgen_dating", "dating-desktop"), "dating-desktop: hero + pills", crop: [560, 40, 700, 160]),
      tile(shot("brgen_radio", "tv-desktop"), "tv-desktop: hero + chips", crop: [380, 40, 680, 220]),
      tile(shot("brgen_radio", "tv-desktop"), "tv-desktop: card + caption", crop: [380, 260, 680, 330]),
      tile(shot("brgen_radio", "radio-desktop"), "radio-desktop: Utvalg label + Bla knapp", crop: [380, 200, 680, 160]),
      tile(shot("brgen_radio", "radio-mobile"), "radio-mobile: Utvalg label", crop: [0, 220, 390, 130]),
      tile(shot("bsdports", "bsdports-mobile"), "bsdports-mobile: top bar", crop: [0, 0, 390, 70]),
      tile(shot("bsdports", "bsdports-mobile"), "bsdports-mobile: mid-list controls", crop: [0, 1750, 390, 220]),
      tile(shot("brgen_messenger", "messenger-desktop"), "messenger-desktop: Meldinger heading box",
           crop: [180, 60, 800, 160])
    ] },
    "c3-crops-c" => { q: 85, font: 26, align: :low, column: [
      tile(mrdamascy("01-menu"), "01-menu: status line 1:1", crop: [0, 0, 500, 60]),
      tile(mrdamascy("01-menu"), "01-menu: hours line 1:1", crop: [0, 250, 500, 90]),
      tile(mrdamascy("03-item-sheet"), "03: ingredient chips 1:1", crop: [0, 470, 500, 260]),
      tile(mrdamascy("05-cart"), "05-cart: empty copy 1:1", crop: [0, 90, 500, 200]),
      tile(shot("brgen_marketplace", "marketplace-desktop"), "marketplace-desktop: info strip + hero",
           crop: [620, 0, 820, 300], scale: 0.9),
      tile(shot("brgen", "brgen-desktop"), "brgen-desktop: composer + floating pill", crop: [780, 60, 660, 320])
    ] },
    "c4-crops-d" => { q: 85, font: 22, align: :low, column: [
      tile(shot("amber", "amber-desktop"), "amber-desktop: wordmark + nav", crop: [380, 30, 720, 180]),
      tile(shot("amber", "amber-desktop"), "amber-desktop: Bymorgen tile", crop: [430, 1520, 580, 360]),
      tile(shot("amber", "amber-desktop"), "amber-desktop: footer wordmark", crop: [420, 2830, 580, 160]),
      tile(shot("amber", "amber-mobile"), "amber-mobile: tile", crop: [0, 580, 390, 320]),
      tile(shot("brgen_dating", "dating-desktop"), "dating-desktop: pills", crop: [560, 110, 760, 200]),
      tile(shot("brgen_radio", "tv-desktop"), "tv-desktop: chips + section", crop: [300, 200, 900, 420], scale: 0.85),
      tile(shot("brgen_radio", "radio-desktop"), "radio-desktop: Utvalgt spor + knapp", crop: [380, 380, 700, 200]),
      tile(shot("brgen_radio", "radio-mobile"), "radio-mobile: spor label", crop: [0, 340, 390, 180]),
      tile(shot("bsdports", "bsdports-mobile"), "bsdports-mobile: import row", crop: [0, 1350, 390, 180]),
      tile(shot("brgen_marketplace", "marketplace-desktop"), "marketplace-desktop: hero price", crop: [60, 400, 620, 220]),
      tile(shot("brgen_maps", "maps-desktop"), "maps-desktop: nav bleed 1:1", crop: [0, 0, 720, 120]),
      tile(mrdamascy("12-vipps-login-mock"), "mrdamascy 12: buttons", crop: [0, 380, 500, 220]),
      tile(mrdamascy("13-staff-board"), "mrdamascy 13: status rows", crop: [0, 100, 500, 220]),
      tile(mrdamascy("07-tracking"), "mrdamascy 07: tail lines", crop: [0, 300, 500, 260]),
      tile(mrdamascy("08-loyalty-guest"), "mrdamascy 08: stempler line", crop: [0, 50, 500, 140])
    ] }
  }.freeze

  module_function

  def run(names)
    names = SHEETS.keys if names.empty?
    unknown = names - SHEETS.keys
    abort "review_sheets: unknown sheet #{unknown.join(', ')}; known: #{SHEETS.keys.join(' ')}" if unknown.any?

    FileUtils.mkdir_p(OUT)
    names.each { |name| render(name, SHEETS.fetch(name)) }
  end

  def render(name, spec)
    rows = spec[:rows] || spec[:column].map { |entry| [entry] }
    sheet = join_all(rows.map { |row| join_all(row.map { |entry| picture(entry, spec) }, :horizontal) }, :vertical)
    path = File.join(OUT, "#{name}.jpg")
    sheet.jpegsave(path, Q: spec.fetch(:q))
    puts "review_sheets: #{name}.jpg #{sheet.width}x#{sheet.height}"
  end

  # One screenshot, cropped and scaled, with its caption above it. A
  # :width_N scale fits the picture to N pixels wide.
  def picture(entry, spec)
    path, caption, crop, scale = entry
    image = Vips::Image.new_from_file(File.join(REVIEW_ROOT, path), access: crop ? :random : :sequential)
    image = image.crop(*crop) if crop
    scale = scale.to_s.delete_prefix("width_").to_f / image.width if scale.is_a?(Symbol)
    image = image.resize(scale) unless scale == 1.0
    label = caption_strip(caption, image.width, spec)
    label ? label.join(image, :vertical, expand: true, background: BG) : image
  end

  # libvips draws text through Pango; a build without it gets a captionless tile.
  def caption_strip(caption, width, spec)
    text = Vips::Image.text(caption, font: "DejaVu Sans #{spec.fetch(:font)}", dpi: 72, width:, align: spec.fetch(:align))
    text.embed(0, 2, width, text.height + 4, background: BG)
  rescue Vips::Error
    nil
  end

  # Pads every image to the row's height (or the column's width) on the
  # background, then joins them with a GAP-pixel shim.
  def join_all(images, direction)
    horizontal = direction == :horizontal
    extent = images.map { |image| horizontal ? image.height : image.width }.max
    padded = images.map do |image|
      horizontal ? image.embed(0, 0, image.width, extent, background: BG) : image.embed(0, 0, extent, image.height, background: BG)
    end
    padded.reduce { |joined, image| joined.join(image, direction, expand: true, background: BG, shim: GAP) }
  end
end

ReviewSheets.run(ARGV) if $PROGRAM_NAME == __FILE__
