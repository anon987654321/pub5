# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require "securerandom"
require "digest"
require_relative "idea_picture"
require_relative "judge"
require_relative "quality"
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
                     inference_profile: nil, subjects_root: nil, direction: "varied", heavy: false)
        @subject = subject.to_s
        raise ArgumentError, "subject must be a simple directory name" unless @subject.match?(/\A[a-zA-Z0-9_-]+\z/)
        @direction = direction.to_s
        unless @direction == "varied" || Studio::Lora::Selfie::DIRECTIONS.key?(@direction)
          raise ArgumentError, "unknown photographic direction"
        end
        @scenes = scenes.nil? ? nil : Array(scenes)
        raise ArgumentError, "selfie series needs at least one scene" if @scenes&.empty?
        @heavy = heavy ? true : false

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
        reference = review_reference
        rendered = []
        series_id = SecureRandom.hex(8)
        record("series_start", series_id:, count: total, inference_profile: @series.inference_profile,
               engine: @series.engine, reference_photographs: @reference_files.length, direction: @direction)
        total.times do |index|
          recipe = if @scenes
                     { "scene" => @scenes[index % @scenes.size], "preset" => "house", "sitting" => index + 1 }
                   else
                     Studio::Lora::Selfie.recipe(index + 1, subject: @subject, direction: @direction)
                   end
          scene = recipe.fetch("scene")
          grade_seed = Studio::Lora::Selfie.grade_seed(index + 1, @subject)
          begin
            stem = "#{@subject}_selfie_#{format("%02d", index + 1)}"
            result = @series.write(scene, film: false, output_stem: stem, grade_seed:,
                                   preset: @heavy ? nil : recipe.fetch("preset"), compiled: recipe.key?("shot"))
            path = result.fetch("still")
            likeness = Studio::Lora::Judge.likeness(reference: reference, candidate: path)
            quality = Studio::Lora::Judge.assess(candidate: path, original: result.dig("capture", "original"), likeness:)
            record("render", series_id:, index: index, scene: scene, path: path, likeness: likeness,
                   recipe: recipe, grade_seed: grade_seed, review: "NOT_REVIEWED",
                   quality: quality, refinement: Studio::Lora::Judge.refinement(quality),
                   grade_sha256: result.dig("capture", "grade_sha256"))
            rendered << path
          rescue StandardError => error
            record("render_attempt", series_id:, index: index, scene: scene,
                   error: "#{error.class}: #{error.message[0, 200]}")
          end
        end

        rendered
      end

      def review_candidate(series_id:, index:, sha256:, decision:)
        raise ArgumentError, "decision must be approve or reject" unless %w[approve reject].include?(decision)
        raise ArgumentError, "invalid series id" unless series_id.to_s.match?(/\A[0-9a-f]{16}\z/)
        raise ArgumentError, "invalid candidate hash" unless sha256.to_s.match?(/\A[0-9a-f]{64}\z/)
        row = private_rows(@ledger_path).reverse.find do |entry|
          entry["kind"] == "render" && entry["subject"] == @subject &&
            entry["series_id"] == series_id && entry["index"] == Integer(index)
        end
        raise ArgumentError, "candidate not recorded" unless row && row["grade_sha256"] == sha256
        path = File.expand_path(row.fetch("path"))
        raise ArgumentError, "candidate outside render directory" unless File.dirname(path) == @directory
        private_file!(path)
        raise ArgumentError, "candidate changed after rendering" unless Digest::SHA256.file(path).hexdigest == sha256
        if decision == "approve" && row.dig("likeness", "state") == "FAIL"
          raise ArgumentError, "cannot approve a failed likeness as a finished portrait"
        end

        event = { "at" => Time.now.utc.iso8601, "series_id" => series_id,
                  "index" => Integer(index), "sha256" => sha256, "decision" => decision,
                  "preset" => row.dig("recipe", "preset"), "direction" => row.dig("recipe", "direction") || "varied" }
        append_preference(event)
        event
      end

      def preferences
        latest = private_rows(preference_path).to_h { |row| [[row["series_id"], row["index"]], row] }.values
        { "reviewed" => latest.size,
          "approved_presets" => latest.select { |row| row["decision"] == "approve" }.map { |row| row["preset"] }.compact.tally,
          "approved_directions" => latest.select { |row| row["decision"] == "approve" }.map { |row| row["direction"] }.compact.tally,
          "rejected_presets" => latest.select { |row| row["decision"] == "reject" }.map { |row| row["preset"] }.compact.tally }
      end

      private

      # Review is separately authorized; generation inputs are not independent
      # evaluation evidence. Without a private holdout, no face scoring runs.
      def review_reference
        directory = File.join(@subjects_root, @subject)
        Studio::Lora::Consent.require!(subject: @subject, subject_directory: directory,
                                      action: :likeness_review, required_sources: ["evaluation_photographs"])
        Studio::Lora::Quality.evaluation_files(subject: @subject, root: @subjects_root).first
      rescue Studio::Lora::Consent::Error, Studio::Lora::Quality::Error, SystemCallError
        nil
      end

      def preference_path
        File.join(@subjects_root, @subject, ".cache", "photographic_preferences.jsonl")
      end

      def private_file!(path)
        stat = File.lstat(path)
        unless stat.file? && !stat.symlink? && stat.uid == Process.uid && stat.nlink == 1 && (stat.mode & 0o077).zero?
          raise ArgumentError, "photographic record must be private and singly linked"
        end
      end

      def private_rows(path)
        return [] unless File.exist?(path) || File.symlink?(path)
        [@subjects_root, File.join(@subjects_root, @subject), File.dirname(path)].each do |parent|
          raise ArgumentError, "refusing symlinked photographic record" if File.symlink?(parent)
        end
        private_file!(path)
        File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
          stat = file.stat
          unless stat.file? && stat.uid == Process.uid && stat.nlink == 1 && (stat.mode & 0o077).zero?
            raise ArgumentError, "photographic record must be private and singly linked"
          end
          raise ArgumentError, "photographic ledger is too large" if stat.size > 16 * 1024 * 1024
          file.flock(File::LOCK_SH)
          file.each_line.map { |line| JSON.parse(line) }
        end
      end

      def append_preference(event)
        path = preference_path
        directory = File.dirname(path)
        subject_directory = File.dirname(directory)
        [@subjects_root, subject_directory, directory].each do |parent|
          raise ArgumentError, "refusing symlinked preference path" if File.symlink?(parent)
        end
        raise ArgumentError, "subject directory is missing" unless File.directory?(subject_directory)
        FileUtils.mkdir_p(directory, mode: 0o700)
        stat = File.lstat(directory)
        raise ArgumentError, "preference directory must be private" unless stat.directory? && stat.uid == Process.uid && (stat.mode & 0o077).zero?
        private_file!(path) if File.exist?(path) || File.symlink?(path)
        File.open(path, File::WRONLY | File::APPEND | File::CREAT | File::NOFOLLOW, 0o600) do |file|
          file.flock(File::LOCK_EX)
          file.puts JSON.generate(event)
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
