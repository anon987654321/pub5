# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require_relative "idea_picture"
require_relative "../lora/lora"

module Studio
  module Visual
    # A bounded, still-only LoRA portrait series. Final graded photographs are
    # written directly to STUDIO/lora/ with a subject/index prefix. No render
    # directory is created per person.
    class SelfieSeries
      LIMIT = 24

      # Subject-specific sittings live in lora/lora.rb with the rest of the craft.
      # Each prompt carries its own environment, moment, lens and light.
      SCENES = Studio::Lora::Selfie::SCENES

      IMAGE_EXTENSIONS = %w[jpg jpeg png webp].freeze

      def initialize(subject:, client: nil, directory: nil, scenes: nil, ledger_path: nil, engine: nil)
        @subject = subject.to_s
        raise ArgumentError, "subject must be a simple directory name" unless @subject.match?(/\A[a-zA-Z0-9_-]+\z/)
        @scenes = scenes.nil? ? nil : Array(scenes)
        raise ArgumentError, "selfie series needs at least one scene" if @scenes&.empty?

        @directory = File.expand_path(directory || IdeaPicture::SUBJECTS)
        @subject_directory = File.join(IdeaPicture::SUBJECTS, @subject)
        @series = IdeaPicture.new(
          subject: @subject, directory: @directory, client:, engine:, lora_only: engine.nil?
        )
        @ledger_path = ledger_path || File.join(IdeaPicture::SUBJECTS, @subject, "ledger.jsonl")
      end

      def preflight! = @series.validate_model!

      def run(count: 6, replace: false)
        total = Integer(count)
        raise ArgumentError, "count must be between 1 and #{LIMIT}" unless total.between?(1, LIMIT)

        preflight!
        previous = previous_render_paths if replace
        rendered = []
        total.times do |index|
          scene = if @scenes
                    @scenes[index % @scenes.size]
                  else
                    Studio::Lora::Selfie.scene(index + 1, subject: @subject)
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
            replace_previous_renders!(keep: rendered)
          else
            record("replace_preserved", previous: previous.length, rendered: rendered.length, expected: total)
          end
        end
        rendered
      end

      # Delete only prior generated image outputs for this subject. Validate
      # every target before unlinking any of them; references, sources, datasets,
      # weights, consent and other subjects are outside these roots by design.
      def replace_previous_renders!(keep: [])
        retained = Array(keep).map { |path| File.expand_path(path) }
        candidates = previous_render_paths.reject { |path| retained.include?(File.expand_path(path)) }
        sidecars = candidates.map { |path| "#{path}.json" }.select { |path| File.exist?(path) || File.symlink?(path) }
        targets = (candidates + sidecars).uniq
        unsafe = targets.reject { |path| safe_generated_file?(path) }
        raise "refusing to delete unsafe or unowned generated output: #{unsafe.join(", ")}" unless unsafe.empty?

        targets.each { |path| File.delete(path) }
        record("replace_delete", deleted: candidates.length, sidecars: sidecars.length)
        candidates.length
      end

      private

      def safe_generated_file?(path)
        expanded = File.expand_path(path)
        roots = [
          @directory,
          File.join(@subject_directory, "out"),
          File.join(IdeaPicture::SUBJECTS, "out", @subject, "selfie_series")
        ].map { |root| File.expand_path(root) }
        root = roots.find { |candidate| expanded.start_with?("#{candidate}#{File::SEPARATOR}") }
        return false unless root && File.directory?(root) && !File.symlink?(root)

        relative = expanded.delete_prefix("#{root}#{File::SEPARATOR}")
        parts = relative.split(File::SEPARATOR)
        cursor = root
        parts[0...-1].each do |part|
          cursor = File.join(cursor, part)
          return false if File.symlink?(cursor) || !File.directory?(cursor)
        end
        stat = File.lstat(expanded)
        stat.file? && !stat.symlink? && stat.uid == Process.uid && stat.nlink == 1
      rescue SystemCallError
        false
      end

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

      def record(kind, **fields)
        directory = File.dirname(@ledger_path)
        raise "refusing symlinked subject ledger directory: #{directory}" if File.symlink?(directory)
        FileUtils.mkdir_p(directory, mode: 0o700)
        File.chmod(0o700, directory)
        raise "refusing symlinked subject ledger: #{@ledger_path}" if File.symlink?(@ledger_path)
        if File.exist?(@ledger_path)
          stat = File.lstat(@ledger_path)
          raise "subject ledger is not a regular file" unless stat.file? && !stat.symlink?
          raise "subject ledger must be singly-linked" unless stat.nlink == 1
          raise "subject ledger is not owned by the current user" unless stat.uid == Process.uid
        end
        File.open(@ledger_path, "a", 0o600) do |file|
          file.puts JSON.generate({ "at" => Time.now.utc.iso8601, "kind" => kind, "subject" => @subject, **fields })
        end
        File.chmod(0o600, @ledger_path)
      end
    end
  end
end
