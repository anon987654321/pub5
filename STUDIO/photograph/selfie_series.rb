# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require_relative "idea_picture"

module Studio
  module Visual
    # A bounded portrait series for a subject with an approved, trained model:
    # one selfie-style scene per prompt, each rendered still-only through
    # IdeaPicture's graded pass, each row recorded in the subject's ledger.
    # This is the committed runner for the selfie chain -- the earlier series
    # exist only as led artefacts; from now the run is reproducible from the
    # tree. Wholesome scenes only: a subject's agreement to being photographed
    # is not a decision to generate intimate framing.
    class SelfieSeries
      LIMIT = 24

      SCENES = [
        "a mirror selfie in a bright bathroom, morning light",
        "a golden-hour car window selfie, sunlight across the cheek",
        "a cafe table selfie, window light from the left, a coffee cup beside",
        "a walking sidewalk selfie, the street softly out of focus",
        "a close-up face selfie, natural window light, no flash",
        "a gym locker mirror selfie after a workout",
        "a rooftop selfie, the city skyline blurred behind",
        "a kitchen selfie while cooking, warm lamp light",
        "a hallway mirror selfie wearing a good jacket",
        "a winter street selfie in soft overcast light, coat collar up",
        "a boat deck selfie, summer light, a lake behind",
        "a backstage-style selfie lit by one warm practical lamp",
      ].freeze

      def initialize(subject:, client: nil, directory: nil, scenes: SCENES, ledger_path: nil)
        @scenes = Array(scenes)
        @subject = subject
        @series = IdeaPicture.new(
          subject: subject,
          directory: directory || default_directory(subject),
          client: client
        )
        @ledger_path = ledger_path || File.join(IdeaPicture::SUBJECTS, "out", @subject, "ledger.jsonl")
      end

      def run(count: 12)
        unless Integer(count).between?(1, LIMIT)
          raise ArgumentError, "count must be between 1 and #{LIMIT}"
        end

        rendered = []
        count.times do |index|
          scene = @scenes[index % @scenes.size]
          begin
            path = @series.write(scene, film: false).fetch("still")
            record("render", index: index, scene: scene, path: path)
            rendered << path
          rescue StandardError => e
            record("render_attempt", index: index, scene: scene,
                   error: "#{e.class}: #{e.message[0, 200]}")
          end
        end
        rendered
      end

      private

      def default_directory(subject)
        File.join(IdeaPicture::SUBJECTS, "out", subject, "selfie_series")
      end

      def record(kind, **fields)
        dir = File.dirname(@ledger_path)
        FileUtils.mkdir_p(dir)
        File.open(@ledger_path, "a") do |f|
          f.puts JSON.generate({ "at" => Time.now.utc.iso8601, "kind" => kind, "subject" => @subject, **fields })
        end
      end
    end
  end
end
