# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require "securerandom"
require_relative "idea_picture"
require_relative "judge"
require_relative "lora"

module Studio
  module Visual
    # A bounded, still-only identity portrait series. The subject's reference
    # photographs and the catalogue's default reference engine are used when
    # available; the pinned LoRA is the fallback. Final graded photographs are
    # written directly to STUDIO/lora/ with a subject/index prefix. No render
    # directory is created per person.
    class SelfieSeries
      LIMIT = 24

      # Subject-specific sittings live in lora/lora.rb with the rest of the craft.
      # Each prompt carries its own environment, moment, lens and light.
      SCENES = Studio::Lora::Selfie::SCENES

      def initialize(subject:, client: nil, directory: nil, scenes: nil, ledger_path: nil, engine: nil,
                     inference_profile: nil, subjects_root: nil)
        @subject = subject.to_s
        raise ArgumentError, "subject must be a simple directory name" unless @subject.match?(/\A[a-zA-Z0-9_-]+\z/)
        @scenes = scenes.nil? ? nil : Array(scenes)
        raise ArgumentError, "selfie series needs at least one scene" if @scenes&.empty?

        @directory = File.expand_path(directory || IdeaPicture::SUBJECTS)
        @subjects_root = File.expand_path(subjects_root || IdeaPicture::SUBJECTS)
        @reference_files = IdeaPicture.reference_files(File.join(@subjects_root, @subject))
        selected_engine = engine
        if selected_engine.nil? && inference_profile.nil? && @reference_files.any?
          selected_engine = Studio::ReplicateClient::Models.default_engine
        end
        @series = IdeaPicture.new(
          subject: @subject, directory: @directory, subjects_root: @subjects_root, client:,
          engine: selected_engine, lora_only: selected_engine.nil?, inference_profile:
        )
        @ledger_path = ledger_path || File.join(@subjects_root, @subject, "ledger.jsonl")
      end

      def preflight! = @series.validate_model!

      # replace: is a compatibility keyword only. All previous portraits,
      # graded renders and sidecars are retained, regardless of its value.
      def run(count: 4, replace: false)
        total = Integer(count)
        raise ArgumentError, "count must be between 1 and #{LIMIT}" unless total.between?(1, LIMIT)

        preflight!
        rendered = []
        series_id = SecureRandom.hex(8)
        record("series_start", series_id:, count: total, inference_profile: @series.inference_profile,
               engine: @series.engine, reference_photographs: @reference_files.length)
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
            likeness = Studio::Lora::Judge.likeness(reference: @reference_files.first, candidate: path)
            record("render", series_id:, index: index, scene: scene, path: path, likeness: likeness)
            rendered << path
          rescue StandardError => error
            record("render_attempt", series_id:, index: index, scene: scene,
                   error: "#{error.class}: #{error.message[0, 200]}")
          end
        end

        rendered
      end

      private

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
