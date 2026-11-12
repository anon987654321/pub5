# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require_relative "idea_picture"

module Studio
  module Visual
    # A bounded, still-only LoRA portrait series. Final graded photographs are
    # written directly to STUDIO/lora/ with a subject/index prefix. No render
    # directory is created per person.
    class SelfieSeries
      LIMIT = 24

      SCENES = [
        "an arm's-length smartphone selfie at a bright cafe window, relaxed candid expression",
        "a city-walk selfie in soft morning light, an understated everyday outfit",
        "a close portrait selfie outdoors in open shade, leafy background softly blurred",
        "a mirror selfie in a tidy, naturally lit hallway, casual jacket",
        "a sunny waterfront selfie with the harbour softly out of focus",
        "a warm kitchen selfie while making coffee, window light from the side",
        "a winter street selfie in soft overcast light, coat collar visible",
        "a rooftop selfie at golden hour, distant skyline softly blurred",
        "a weekend market selfie with natural candid expression and gentle background detail",
        "a quiet home-window selfie in late afternoon light, simple neutral clothing",
      ].freeze

      IMAGE_EXTENSIONS = %w[jpg jpeg png webp].freeze

      def initialize(subject:, client: nil, directory: nil, scenes: SCENES, ledger_path: nil)
        @subject = subject.to_s
        raise ArgumentError, "subject must be a simple directory name" unless @subject.match?(/\A[a-zA-Z0-9_-]+\z/)
        @scenes = Array(scenes)
        raise ArgumentError, "selfie series needs at least one scene" if @scenes.empty?

        @directory = File.expand_path(directory || IdeaPicture::SUBJECTS)
        @subject_directory = File.join(IdeaPicture::SUBJECTS, @subject)
        @series = IdeaPicture.new(
          subject: @subject, directory: @directory, client:
        )
        @ledger_path = ledger_path || File.join(IdeaPicture::SUBJECTS, @subject, "ledger.jsonl")
      end

      def run(count: 12, replace: false)
        total = Integer(count)
        raise ArgumentError, "count must be between 1 and #{LIMIT}" unless total.between?(1, LIMIT)

        # Consent is checked before a provider schema request, cleanup or render.
        required = Studio::Lora::Consent.required_source_sets(
          subject: @subject, subject_directory: @subject_directory
        )
        Studio::Lora::Consent.require!(
          subject: @subject, subject_directory: @subject_directory, required_sources: required
        )
        @series.validate_model!
        removed = clear_previous_renders! if replace
        record("replace_cleanup", deleted: removed) if replace

        rendered = []
        total.times do |index|
          scene = @scenes[index % @scenes.size]
          begin
            stem = "#{@subject}_selfie_#{format("%02d", index + 1)}"
            path = @series.write(scene, film: false, output_stem: stem).fetch("still")
            record("render", index: index, scene: scene, path: path)
            rendered << path
          rescue StandardError => error
            record("render_attempt", index: index, scene: scene,
                   error: "#{error.class}: #{error.message[0, 200]}")
          end
        end
        rendered
      end

      private

      def clear_previous_renders!
        patterns = IMAGE_EXTENSIONS.flat_map do |ext|
          [
            File.join(@directory, "#{@subject}_selfie_*.#{ext}"),
            File.join(@directory, "postpro_#{@subject}_selfie_*.#{ext}"),
          ]
        end
        legacy_output = File.join(IdeaPicture::SUBJECTS, @subject, "out")
        if File.directory?(legacy_output) && !File.symlink?(legacy_output)
          patterns.concat(IMAGE_EXTENSIONS.map { |ext| File.join(legacy_output, "**", "*.#{ext}") })
        end
        legacy_series = File.join(IdeaPicture::SUBJECTS, "out", @subject, "selfie_series")
        if File.directory?(legacy_series) && !File.symlink?(legacy_series)
          patterns.concat(IMAGE_EXTENSIONS.map { |ext| File.join(legacy_series, "*.#{ext}") })
        end

        paths = patterns.flat_map { |pattern| Dir.glob(pattern) }.uniq
        paths.count do |path|
          next false if File.symlink?(path) || !File.file?(path)

          File.delete(path)
          true
        end
      end

      def record(kind, **fields)
        directory = File.dirname(@ledger_path)
        FileUtils.mkdir_p(directory)
        File.open(@ledger_path, "a", 0o600) do |file|
          file.puts JSON.generate({ "at" => Time.now.utc.iso8601, "kind" => kind, "subject" => @subject, **fields })
        end
        File.chmod(0o600, @ledger_path)
      end
    end
  end
end
