# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require "securerandom"
require_relative "idea_picture"
require_relative "../lora/lora"

module Studio
  module Visual
    # A bounded, still-only LoRA portrait series. Final graded photographs are
    # written directly to STUDIO/lora/ with a subject/index prefix. No render
    # directory is created per person.
    class SelfieSeries
      LIMIT = 24

      # The sittings live in lora/lora.rb with the rest of the craft: ten
      # radically different environments and moments, each stating its own crop,
      # lens and light.
      SCENES = Studio::Lora::Selfie::SCENES

      IMAGE_EXTENSIONS = %w[jpg jpeg png webp].freeze

      def initialize(subject:, client: nil, directory: nil, scenes: SCENES, ledger_path: nil, engine: nil)
        @subject = subject.to_s
        raise ArgumentError, "subject must be a simple directory name" unless @subject.match?(/\A[a-zA-Z0-9_-]+\z/)
        @scenes = Array(scenes)
        raise ArgumentError, "selfie series needs at least one scene" if @scenes.empty?

        @directory = File.expand_path(directory || IdeaPicture::SUBJECTS)
        @subject_directory = File.join(IdeaPicture::SUBJECTS, @subject)
        @series = IdeaPicture.new(
          subject: @subject, directory: @directory, client:, engine:
        )
        @ledger_path = ledger_path || File.join(IdeaPicture::SUBJECTS, @subject, "ledger.jsonl")
      end

      def run(count: 12, replace: false)
        total = Integer(count)
        raise ArgumentError, "count must be between 1 and #{LIMIT}" unless total.between?(1, LIMIT)

        @series.validate_model!
        previous = previous_render_paths if replace
        rendered = []
        total.times do |index|
          scene = if @scenes.equal?(SCENES)
                    Studio::Lora::Selfie.scene(index + 1)
                  else
                    @scenes[index % @scenes.size]
                  end
          begin
            stem = "#{@subject}_selfie_#{format("%02d", index + 1)}"
            path = @series.write(
              scene, film: false, output_stem: stem,
              grade_seed: Studio::Lora::Selfie.grade_seed(index + 1, @subject)
            ).fetch("still")
            record("render", index: index, scene: scene, path: path)
            rendered << path
          rescue StandardError => error
            record("render_attempt", index: index, scene: scene,
                   error: "#{error.class}: #{error.message[0, 200]}")
          end
        end

        if replace
          complete = rendered.length == total && rendered.all? { |path| File.file?(path) && !File.symlink?(path) }
          if complete
            archived = archive_previous_renders!(previous - rendered)
            record("replace_archive", archived:)
          else
            record("replace_preserved", previous: previous.length, rendered: rendered.length, expected: total)
          end
        end
        rendered
      end

      private

      def previous_render_paths
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

        patterns.flat_map { |pattern| Dir.glob(pattern) }.uniq.select do |path|
          File.file?(path) && !File.symlink?(path)
        end
      end

      # Replacement is a commit-like operation: old files move to a private,
      # ignored archive only after every new render exists. A failed/partial run
      # leaves the previous series untouched.
      def archive_previous_renders!(paths)
        candidates = Array(paths).select { |path| File.file?(path) && !File.symlink?(path) }
        return 0 if candidates.empty?

        archive_root = File.join(@directory, @subject, "out", "archive",
                                 "#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}-#{SecureRandom.hex(3)}")
        FileUtils.mkdir_p(archive_root, mode: 0o700)
        File.chmod(0o700, archive_root)
        moved = []
        begin
          candidates.each do |source|
            expanded = File.expand_path(source)
            raise "refusing to archive a path outside the render root" unless expanded.start_with?("#{@directory}#{File::SEPARATOR}")
            raise "refusing to archive a symlink or non-file" if File.symlink?(source) || !File.file?(source)

            destination = File.join(archive_root, File.basename(source))
            raise "archive destination already exists" if File.exist?(destination)
            File.rename(source, destination)
            File.chmod(0o600, destination)
            moved << [source, destination]
          end
        rescue StandardError
          moved.reverse_each do |source, destination|
            File.rename(destination, source) if File.file?(destination) && !File.exist?(source)
          rescue SystemCallError
            # Preserve the archive rather than deleting evidence if rollback itself fails.
          end
          raise
        end
        moved.length
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
