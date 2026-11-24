#!/usr/bin/env ruby
# frozen_string_literal: true

# Calibrate the grade against real film, not against taste.
#
# The film-stock looks in postpro are assertions until they are measured
# against genuine reference frames: scans of the actual stocks, shot and
# developed under known conditions. Drop those scans in a PRIVATE directory
# (they never enter the checkout), point this tool at them and at a directory
# of graded masters, and it reports, frame pair by frame pair, whether the
# grade sits inside the reference envelope or has drifted from it:
#
#   ruby STUDIO/postpro/calibrate.rb --reference PRIVATE_SCANS --graded PRIVATE_GRADES --json
#
# Pairing is by identical basename, so name each grade after its reference.
# The readings reuse Postpro::Uncanny (texture, specular spread, clipping,
# tonal range) plus per-channel means and deviations. They are whole-frame
# proxies - they can prove drift, they cannot prove a photograph. The final
# verdict on a look remains a human comparing full-size frames.
#
# With no reference directory the tool reports NOT_CALIBRATED rather than
# nothing: an uncalibrated stock look is a claim, not a fact (TRUTHFUL_STATUS).

require "json"
require "optparse"
require "yaml"
require_relative "uncanny"

module Postpro
  module Calibrate
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze

    # How far a grade may drift from its reference before the pair is called
    # OUTSIDE_ENVELOPE. texture/tonal_range/specular_spread are relative
    # bands; clipping is absolute percentage points (blown detail is destroyed,
    # not styled).
    ENVELOPE = {
      "texture" => 0.25,
      "specular_spread" => 0.30,
      "clipping" => 1.0,
      "tonal_range" => 0.20,
    }.freeze

    class Error < StandardError; end

    module_function

    # Pair reference scans with grades by identical basename, sorted so the
    # receipt is stable. Unmatched files are reported, never silently dropped.
    def pair(reference_dir, graded_dir)
      reference = image_files(reference_dir, "reference")
      graded = image_files(graded_dir, "graded")
      common = reference.keys & graded.keys
      {
        "pairs" => common.sort.map { |name| [reference.fetch(name), graded.fetch(name)] },
        "unmatched_reference" => (reference.keys - common).sort,
        "unmatched_graded" => (graded.keys - common).sort,
      }
    end

    def image_files(directory, label)
      raise Error, "#{label} directory is missing or symlinked" unless File.directory?(directory) && !File.symlink?(directory)

      stat = File.lstat(directory)
      raise Error, "#{label} directory must be owner-only (0700)" unless stat.uid == Process.uid && (stat.mode & 0o077).zero?

      Dir.children(directory).sort.select { |name| IMAGE_EXTENSIONS.include?(File.extname(name).downcase) }
         .to_h { |name| [name, File.join(directory, name)] }
    end

    # Pure envelope decision, so tests need no images. Readings are the four
    # Uncanny metrics as strings/numbers; nil specular_spread (a frame with no
    # bright pixels) skips that axis rather than inventing a value.
    def verdict(reference, graded, envelope: ENVELOPE)
      deltas = {}
      failed = []
      envelope.each do |axis, band|
        ref = reference[axis]
        got = graded[axis]
        next if ref.nil? || got.nil?

        ref = ref.to_f
        got = got.to_f
        deltas[axis] = (got - ref).round(6)
        outside = if axis == "clipping"
                    got > ref + band
                  else
                    scale = [ref.abs, 1.0e-6].max
                    (got - ref).abs > scale * band
                  end
        failed << axis if outside
      end
      {
        "state" => failed.empty? ? "WITHIN_ENVELOPE" : "OUTSIDE_ENVELOPE",
        "outside_axes" => failed,
        "deltas" => deltas,
      }
    end

    # One frame: the four Uncanny readings plus per-channel mean and deviation.
    def read(path)
      reading = Postpro::Uncanny.read(path)
      image = Vips::Image.new_from_file(path)
      image = image.flatten if image.has_alpha?
      bands = [image[0], image[1], image[2]].map { |band| { "mean" => band.avg.round(4), "deviation" => band.deviate.round(4) } }
      {
        "texture" => reading.texture,
        "specular_spread" => reading.specular_spread,
        "clipping" => reading.clipping,
        "tonal_range" => reading.tonal_range,
        "channels" => bands,
      }
    end

    def report(reference_dir, graded_dir)
      pairing = pair(reference_dir, graded_dir)
      rows = pairing.fetch("pairs").map do |reference_path, graded_path|
        reference = read(reference_path)
        graded = read(graded_path)
        {
          "pair" => File.basename(reference_path),
          "reference" => reference,
          "graded" => graded,
          "verdict" => verdict(reference, graded),
        }
      end
      drifted = rows.select { |row| row.dig("verdict", "state") == "OUTSIDE_ENVELOPE" }
      {
        "schema" => "postpro.calibration.v1",
        "read_only" => true,
        "provider_calls" => 0,
        "state" => rows.empty? ? "NOT_CALIBRATED" : drifted.empty? ? "WITHIN_ENVELOPE" : "DRIFTED",
        "envelope" => ENVELOPE,
        "pair_count" => rows.length,
        "drifted_count" => drifted.length,
        "unmatched_reference" => pairing.fetch("unmatched_reference"),
        "unmatched_graded" => pairing.fetch("unmatched_graded"),
        "pairs" => rows,
        "limits" => "Whole-frame proxies: drift here proves the grade moved away from the reference; agreement here does not prove the photograph. Judge full-size frames by eye for the final word.",
      }
    end

    def not_calibrated(reason)
      {
        "schema" => "postpro.calibration.v1",
        "read_only" => true,
        "provider_calls" => 0,
        "state" => "NOT_CALIBRATED",
        "reason" => reason,
        "limits" => "Stock looks remain unverified assertions until reference scans are measured.",
      }
    end

    def run_cli(argv)
      options = { reference: nil, graded: nil, json: false }
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby STUDIO/postpro/calibrate.rb --reference DIR --graded DIR [--json]"
        parser.on("--reference DIR", "Private directory of real film reference scans (0700)") { |value| options[:reference] = value }
        parser.on("--graded DIR", "Private directory of graded masters, named after their references (0700)") { |value| options[:graded] = value }
        parser.on("--json", "Print the full machine-readable receipt") { options[:json] = true }
        parser.on("-h", "--help", "Show this help") { puts parser; return 0 }
      end.parse!(argv)

      if options[:reference].to_s.empty? || options[:graded].to_s.empty?
        receipt = not_calibrated("no reference or graded directory supplied")
        puts JSON.pretty_generate(receipt)
        return 2
      end

      receipt = report(File.expand_path(options[:reference]), File.expand_path(options[:graded]))
      if options[:json]
        puts JSON.pretty_generate(receipt)
      else
        puts "calibration: #{receipt.fetch("state")} (#{receipt.fetch("pair_count")} pairs, #{receipt.fetch("drifted_count")} drifted)"
        receipt.fetch("pairs").each do |row|
          verdict = row.fetch("verdict")
          next if verdict.fetch("outside_axes").empty?

          puts "  #{row.fetch("pair")}: outside #{verdict.fetch("outside_axes").join(", ")}"
        end
        puts receipt.fetch("limits")
      end
      receipt.fetch("state") == "WITHIN_ENVELOPE" ? 0 : 1
    rescue Error, SystemCallError, IOError => error
      warn "BLOCKED: #{error.class}: #{error.message}"
      2
    end
  end
end

exit Postpro::Calibrate.run_cli(ARGV) if $PROGRAM_NAME == __FILE__
