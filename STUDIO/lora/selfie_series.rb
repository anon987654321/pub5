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

      def initialize(subject:, client: nil, directory: nil, scenes: nil, ledger_path: nil, engine: nil)
        @subject = subject.to_s
        raise ArgumentError, "subject must be a simple directory name" unless @subject.match?(/\A[a-zA-Z0-9_-]+\z/)
        @scenes = scenes.nil? ? nil : Array(scenes)
        raise ArgumentError, "selfie series needs at least one scene" if @scenes&.empty?

        @directory = File.expand_path(directory || IdeaPicture::SUBJECTS)
        @series = IdeaPicture.new(
          subject: @subject, directory: @directory, client:, engine:, lora_only: engine.nil?
        )
        @ledger_path = ledger_path || File.join(IdeaPicture::SUBJECTS, @subject, "ledger.jsonl")
      end

      def preflight! = @series.validate_model!

      # replace: is a compatibility keyword only. All previous portraits,
      # graded renders and sidecars are retained, regardless of its value.
      def run(count: 6, replace: false)
        total = Integer(count)
        raise ArgumentError, "count must be between 1 and #{LIMIT}" unless total.between?(1, LIMIT)

        preflight!
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
