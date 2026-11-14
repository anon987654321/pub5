# frozen_string_literal: true

# Refuse to ship a frame that is worse than a real photograph of the subject.
# These whole-frame readings are useful proxies, not face recognition,
# composition judgement or a calibrated perceptual colour-difference score.
#
#   ruby STUDIO/lora/judge.rb --calibrate PRIVATE_REFERENCE_DIR
#   ruby STUDIO/lora/judge.rb PRIVATE_RENDER_DIR
#   STUDIO_LORA_THRESHOLDS=/private/path/thresholds.yml ruby STUDIO/lora/judge.rb DIR
#
# Calibration needs at least five regular, non-symlink images outside the
# checkout. By default it prints a path-free YAML document to stdout. An
# explicit --output writes a new mode-0600 file outside the checkout; it never
# overwrites an existing file or the tracked fallback thresholds.

require "json"
require "optparse"
require "pathname"
require "yaml"
require_relative "../output_paths"
require_relative "../postpro/uncanny"

module Studio
  module Lora
    module Judge
      THRESHOLDS_FILE = File.join(__dir__, "thresholds.yml")
      IMAGE_EXT = %w[.jpg .jpeg .png .webp].freeze
      MIN_REFERENCE_IMAGES = 5

      METRIC_RANGES = {
        "texture" => 0.0..4.0,
        "tonal_range" => 0.0..0.5,
        "clipping" => 0.0..100.0,
        "specular_spread" => 0.0..0.5
      }.freeze

      class Error < StandardError; end
      class CalibrationError < Error; end
      class ThresholdError < Error; end

      CHECKS = {
        "texture" => {
          direction: :floor,
          fault: "waxy, over-smoothed skin — the model rendered a face with no pores",
          remedy: "lower guidance_scale, or add grain in postpro; the negative prompt already asks against it"
        },
        "tonal_range" => {
          direction: :floor,
          fault: "flat and veiled — no real blacks, the whole frame sits in the midtones",
          remedy: "a grade may have lifted the shadows; check postpro before blaming the render"
        },
        "clipping" => {
          direction: :ceiling,
          fault: "blown highlights — detail destroyed rather than rolled off",
          remedy: "lower guidance_scale; compare with the calibrated reference ceiling"
        },
        "specular_spread" => {
          direction: :ceiling,
          fault: "plastic sheen — highlights pooling on the skin like wet vinyl",
          remedy: "the 'glossy skin' and 'editorial beauty lighting' phrasings invite this"
        }
      }.freeze

      module_function

      def inside_checkout_path?(candidate)
        expanded = File.expand_path(candidate)
        root = Studio::OutputPaths::REPOSITORY_ROOT
        expanded == root || expanded.start_with?("#{root}#{File::SEPARATOR}") ||
          Studio::OutputPaths.inside_repository?(expanded)
      end

      def thresholds_path
        configured = ENV.fetch("STUDIO_LORA_THRESHOLDS", "").strip
        return THRESHOLDS_FILE if configured.empty?

        path = File.expand_path(configured)
        raise ThresholdError, "threshold override must not be a symlink" if File.symlink?(path)
        if inside_checkout_path?(path)
          raise ThresholdError, "private threshold overrides must live outside the checkout"
        end
        path
      end

      def load_thresholds
        path = thresholds_path
        raise ThresholdError, "threshold file is missing or unreadable: #{File.basename(path)}" unless
          File.file?(path) && File.readable?(path)
        raise ThresholdError, "threshold file must not be a symlink" if File.symlink?(path)

        document = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
        raise ThresholdError, "threshold YAML root must be a mapping" unless document.is_a?(Hash)

        validate_thresholds!(document["thresholds"])
      rescue Psych::Exception, SystemCallError, IOError => error
        raise ThresholdError, "cannot load thresholds: #{error.message}"
      end

      # A bad threshold must fail closed. Strings, NaN, missing dimensions and
      # values outside a metric's physical range must not silently pass a frame.
      def validate_thresholds!(raw)
        raise ThresholdError, "thresholds must be a mapping" unless raw.is_a?(Hash)
        unless raw.keys.all? { |key| key.is_a?(String) }
          raise ThresholdError, "threshold keys must be strings"
        end

        missing = CHECKS.keys - raw.keys
        unknown = raw.keys - CHECKS.keys
        raise ThresholdError, "missing threshold(s): #{missing.join(', ')}" unless missing.empty?
        raise ThresholdError, "unknown threshold(s): #{unknown.join(', ')}" unless unknown.empty?

        CHECKS.keys.to_h do |metric|
          value = raw.fetch(metric)
          range = METRIC_RANGES.fetch(metric)
          unless value.is_a?(Numeric) && value.to_f.finite? && range.cover?(value.to_f)
            raise ThresholdError, "#{metric} must be a finite number in #{range.begin}..#{range.end}"
          end

          [metric, value.to_f]
        end.freeze
      end

      # Contact sheets are for comparing takes, not candidate photographs.
      # Prefer the sidecar schema over a filename convention, while retaining
      # the old prefix exclusion for sheets created before sidecars existed.
      def contact_sheet_file?(path)
        name = path.basename.to_s
        return true if name.match?(/\Acontact_sheet/i) || name.match?(/_contact(?:_v\d+)?\.[^.]+\z/i)

        sidecar = "#{path}.json"
        return false unless File.file?(sidecar) && !File.symlink?(sidecar)

        data = JSON.parse(File.read(sidecar, encoding: "UTF-8"))
        [data["schema"], data.dig("postpro", "schema")].include?("postpro.contact.v1")
      rescue JSON::ParserError, SystemCallError, TypeError
        false
      end

      def frames_in(dir, match)
        directory = Pathname.new(dir)
        return [] unless directory.directory? && !directory.symlink?

        directory.children.select do |path|
          next false unless IMAGE_EXT.include?(path.extname.downcase)
          next false if path.symlink? || contact_sheet_file?(path)

          stat = path.lstat
          stat.file? && stat.size.positive? && File.readable?(path)
        rescue SystemCallError
          false
        end.then do |found|
          found = found.select { |path| path.basename.to_s.include?(match) } if match
          found.sort_by { |path| path.basename.to_s }
        end
      end

      def reference_directory!(dir)
        expanded = File.expand_path(dir)
        path = Pathname.new(expanded)
        raise CalibrationError, "reference path is not a directory or is a symlink" unless
          path.directory? && !path.symlink?

        real = path.realpath.to_s
        if inside_checkout_path?(expanded) || inside_checkout_path?(real)
          raise CalibrationError, "reference photographs must be stored outside the checkout"
        end
        real
      end

      def validate_reading!(reading, context:)
        CHECKS.each_key do |metric|
          unless reading.respond_to?(metric)
            raise CalibrationError, "#{context}: reading is missing #{metric}"
          end

          value = reading.public_send(metric)
          range = METRIC_RANGES.fetch(metric)
          unless value.is_a?(Numeric) && value.to_f.finite? && range.cover?(value.to_f)
            raise CalibrationError, "#{context}: #{metric} is not a finite value in #{range.begin}..#{range.end}"
          end
        end
        reading
      end

      # A reference set defines an outward-rounded min/max envelope. It is an
      # intentionally simple comparison, not a statistical confidence interval.
      # Multiple images prevent one accidental file from replacing calibration;
      # no filename, path or image hash is persisted.
      def calibrate(dir, match, output: nil)
        reference_dir = reference_directory!(dir)
        frames = frames_in(reference_dir, match)
        if frames.length < MIN_REFERENCE_IMAGES
          raise CalibrationError,
                "calibration needs at least #{MIN_REFERENCE_IMAGES} regular reference images; found #{frames.length}"
        end

        readings = frames.map do |path|
          validate_reading!(Postpro::Uncanny.read(path.to_s), context: path.basename.to_s)
        end

        thresholds = CHECKS.to_h do |metric, spec|
          values = readings.map { |reading| reading.public_send(metric).to_f }
          # Round outward, never to nearest: serialization can only grow the envelope.
          value = if spec[:direction] == :floor
                    (values.min * 1e6).floor / 1e6
                  else
                    (values.max * 1e6).ceil / 1e6
                  end
          [metric, value]
        end
        validate_thresholds!(thresholds)

        document = calibration_document(thresholds, image_count: frames.length)
        if output
          path = write_calibration(output, document)
          puts "ok: calibrated #{frames.length} image(s) -> #{path}"
        else
          $stdout.write(document)
        end
        thresholds
      end

      def calibration_document(thresholds, image_count:)
        rows = thresholds.map { |metric, value| "  #{metric}: #{format('%.6f', value)}" }.join("\n")
        <<~YAML
          # Aggregate measurements only; no source paths, filenames or image hashes.
          calibration:
            image_count: #{Integer(image_count)}
            method: "outward-rounded minimum/maximum envelope"
          thresholds:
          #{rows}
        YAML
      end

      # Explicit calibration output is a new private file outside the checkout.
      # EXCL avoids races and accidental replacement; mode 0600 ignores umask.
      def write_calibration(output, document)
        path = File.expand_path(output)
        raise CalibrationError, "calibration output parent directory must already exist" unless
          File.directory?(File.dirname(path))
        raise CalibrationError, "calibration output must not be a symlink" if File.symlink?(path)
        if inside_checkout_path?(path)
          raise CalibrationError, "calibration output must be outside the checkout"
        end

        created = false
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          created = true
          file.write(document)
          file.flush
          file.fsync
        end
        File.chmod(0o600, path)
        path
      rescue Errno::EEXIST
        raise CalibrationError, "calibration output already exists; choose a new path"
      rescue SystemCallError, IOError => error
        File.delete(path) if created && File.file?(path)
        raise CalibrationError, "cannot write calibration output: #{error.message}"
      end

      def faults_for(reading, thresholds)
        limits = validate_thresholds!(thresholds)
        validate_reading!(reading, context: "candidate")
        CHECKS.filter_map do |metric, spec|
          limit = limits.fetch(metric)
          value = reading.public_send(metric).to_f
          breached = spec[:direction] == :floor ? value < limit : value > limit
          next unless breached

          { metric: metric, value: value, limit: limit, fault: spec[:fault], remedy: spec[:remedy] }
        end
      end

      def run(argv)
        options = { match: nil, quarantine: false, calibrate: nil, output: nil }
        OptionParser.new do |parser|
          parser.banner = "usage: judge.rb DIR [--match STR] [--quarantine] | --calibrate PRIVATE_DIR [--output PRIVATE_FILE]"
          parser.on("--match STR", "only files whose name contains STR") { |value| options[:match] = value }
          parser.on("--quarantine", "move rejected frames to DIR/rejected rather than only naming them") do
            options[:quarantine] = true
          end
          parser.on("--calibrate DIR", "measure a private reference directory and print YAML") do |value|
            options[:calibrate] = value
          end
          parser.on("--output PATH", "write a new mode-0600 calibration YAML outside the checkout") do |value|
            options[:output] = value
          end
        end.parse!(argv)

        if options[:calibrate]
          raise CalibrationError, "unexpected positional arguments after --calibrate" unless argv.empty?
          calibrate(options[:calibrate], options[:match], output: options[:output])
          return 0
        end
        raise CalibrationError, "--output is only valid with --calibrate" if options[:output]

        dir = Pathname.new(argv.fetch(0) { raise CalibrationError, "usage: judge.rb DIR [--match STR] [--quarantine]" }).expand_path
        raise CalibrationError, "not a directory: #{dir}" unless dir.directory? && !dir.symlink?

        thresholds = load_thresholds
        frames = frames_in(dir, options[:match])
        raise CalibrationError, "no candidate images in #{dir}" if frames.empty?

        rejected = []
        frames.each do |path|
          faults = faults_for(Postpro::Uncanny.read(path.to_s), thresholds)
          if faults.empty?
            puts "ok:   #{path.basename}"
            next
          end

          rejected << path
          puts "FAIL: #{path.basename}"
          faults.each do |fault|
            comparison = CHECKS[fault[:metric]][:direction] == :floor ? "below floor" : "above ceiling"
            puts format("        %s %.4f — %s %.4f", fault[:metric], fault[:value], comparison, fault[:limit])
            puts "        #{fault[:fault]}"
            puts "        #{fault[:remedy]}"
          end
        end

        puts
        puts "#{frames.length - rejected.length}/#{frames.length} frames clear the whole-frame reference envelope"

        if rejected.any? && options[:quarantine]
          target = dir.join("rejected")
          raise CalibrationError, "refusing a symlinked quarantine directory" if target.symlink?
          target.mkpath
          rejected.each { |path| File.rename(path.to_s, target.join(path.basename).to_s) }
          puts "ok: moved #{rejected.length} frame(s) to #{target} — moved, not deleted"
        end

        rejected.empty? ? 0 : 1
      rescue Error, Psych::Exception, SystemCallError, IOError, ArgumentError, TypeError => error
        warn "warn: judge refused: #{error.message}"
        2
      end
    end
  end
end

exit Studio::Lora::Judge.run(ARGV) if $PROGRAM_NAME == __FILE__
