# frozen_string_literal: true

require "json"
require "fileutils"
require "rbconfig"
require "securerandom"
require_relative "../output_paths"
require_relative "../replicate/client"
require_relative "../subprocess"
require_relative "../lora/consent"
require_relative "../lora/lora"

module Studio
  module Visual
    class IdeaPicture
      FILM = "prunaai/p-video-2-pro"
      # The module root is STUDIO. The flatten (b5acc93bc) moved this file one
      # level up out of photograph/generators/ but left the two-step climb, so
      # ROOT answered the repository root and every path built from it — the
      # Lora subjects, the output-path safety rails — pointed outside the tree.
      ROOT = File.expand_path("..", __dir__)
      SUBJECTS = File.join(ROOT, "lora").freeze
      # The photography craft appended to every still prompt lives in
      # lora/lora.rb as Studio::Lora::Craft: geometry, light direction and
      # expression are decided here, where a grade cannot add them.
      PHOTOGRAPHIC_CRAFT = Studio::Lora::Craft::PHOTOGRAPHIC_CRAFT

      def initialize(
        client: nil,
        directory: SUBJECTS,
        subject: ENV.fetch("STUDIO_PHOTOGRAPH_SUBJECT", "ragnhild"),
        model_manifest: nil
      )
        @client = client
        @directory = directory
        @subject = subject.to_s
        raise ArgumentError, "subject must be a simple directory name" unless @subject.match?(/\A[a-zA-Z0-9_-]+\z/)

        @subject_directory = File.join(SUBJECTS, @subject)
        @model_manifest = model_manifest || default_model_manifest
      end

      def write(words, film: true, duration: 5, output_stem: nil, grade_seed: nil)
        require_subject_consent!
        validate_model!
        validate_film_model! if film
        FileUtils.mkdir_p(@directory)
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")
        stem = [safe_stem(output_stem || @subject), stamp, SecureRandom.hex(3)].join("_")
        still = render_still(words, stem, grade_seed:)
        return { "still" => still } unless film

        { "still" => still, "clip" => render_film(words, still, stem, duration) }
      end

      # Animate an existing LoRA still; never regenerate or overwrite its source.
      def animate(still, words, duration: 5)
        source = File.expand_path(still.to_s)
        raise ArgumentError, "source still is missing" unless File.file?(source) && !File.symlink?(source)
        raise ArgumentError, "source still must be jpg, png or webp" unless %w[.jpg .jpeg .png .webp].include?(File.extname(source).downcase)
        raise ArgumentError, "source still exceeds 25 MB" if File.size(source) > 25 * 1024 * 1024

        seconds = Integer(duration)
        raise ArgumentError, "duration must be between 1 and 10 seconds" unless seconds.between?(1, 10)

        require_subject_consent!
        validate_film_model!
        FileUtils.mkdir_p(@directory)
        stamp = "#{safe_stem(@subject)}_film_#{Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")}_#{SecureRandom.hex(3)}"
        { "still" => source, "clip" => render_film(words, source, stamp, seconds) }
      end

      def validate_model!
        model = still_model
        return model if @validated_still_model == model

        names = client.input_names(model)
        raise "Replicate model is unavailable or has no readable input schema: #{model}" if names.empty?

        required = still_input("").keys.map(&:to_s)
        missing = required - names
        raise "Replicate model #{model} is missing inputs used by the still renderer: #{missing.join(", ")}" unless missing.empty?

        @validated_still_model = model
        model
      end

      def validate_film_model!
        return FILM if @validated_film_model

        names = client.input_names(FILM)
        raise "Replicate film model is unavailable or has no readable input schema: #{FILM}" if names.empty?

        required = %w[prompt image duration mode aspect_ratio resolution]
        missing = required - names
        raise "Replicate film model #{FILM} is missing inputs used by the animation renderer: #{missing.join(", ")}" unless missing.empty?

        @validated_film_model = FILM
        FILM
      end

      private

      def require_subject_consent!
        required = Studio::Lora::Consent.required_source_sets(
          subject: @subject, subject_directory: @subject_directory
        )
        Studio::Lora::Consent.require!(
          subject: @subject, subject_directory: @subject_directory, required_sources: required
        )
      end

      def client
        @client ||= Studio::ReplicateClient.new
      end

      def render_still(words, stem, grade_seed: nil)
        path = File.join(@directory, "#{safe_stem(stem)}.jpg")
        raise "refusing to replace an existing still: #{path}" if File.exist?(path)

        output = client.predict(still_model, still_input(words), timeout: 600)
        client.download_url(first_url(output), path)
        graded = grade(path, seed: grade_seed)
        File.delete(path) if graded != path && File.file?(path)
        graded
      end

      def render_film(words, still, stamp, duration)
        path = File.join(@directory, "#{safe_stem(stamp)}.mp4")
        raise "refusing to replace an existing film: #{path}" if File.exist?(path)

        output = client.predict(FILM, film_input(words, still, duration), timeout: 600)
        client.download_url(first_url(output), path)
        path
      end

      def still_input(words)
        {
          prompt: photographic(words),
          model: "dev",
          aspect_ratio: "2:3",
          num_outputs: 1,
          guidance_scale: 2.5,
          num_inference_steps: 45,
          output_format: "jpg",
          output_quality: 95,
          go_fast: false,
          lora_scale: 1.0,
        }
      end

      def film_input(words, still, duration)
        {
          prompt: "The same photograph, held, one slow motion. #{words}",
          image: client.upload_file(still, subject: @subject),
          duration:,
          mode: "quality",
          aspect_ratio: "2:3",
          resolution: "768p",
        }
      end

      def photographic(words)
        env = subject_env
        parts = [
          env["TRIGGER"], env["DESCRIPTOR"], words, PHOTOGRAPHIC_CRAFT
        ]
        parts.compact.join(", ")
      end

      def subject_env
        path = File.join(@subject_directory, "subject.env")
        return {} unless File.file?(path)

        File.foreach(path).each_with_object({}) do |line, env|
          next if line.strip.empty? || line.strip.start_with?("#")

          key, value = line.strip.split("=", 2)
          next unless value

          value = value.strip
          value = value[1..-2] if value.length >= 2 && value.start_with?('"') && value.end_with?('"')
          env[key] = value
        end
      end

      def default_model_manifest
        configured = subject_env["MODEL"].to_s.strip
        configured = @subject if configured.empty?
        raise ArgumentError, "MODEL in #{@subject}/subject.env must be a simple directory name" unless configured.match?(/\A[a-zA-Z0-9_.-]+\z/)

        File.join(@subject_directory, "weights", configured, "replicate_training.json")
      end

      def still_model
        path = @model_manifest
        if File.file?(path)
          version = JSON.parse(File.read(path))["version"].to_s
          raise "training manifest has no valid owner/model:version: #{path}" unless version.match?(/\A[^\/\s:]+\/[^:\s]+:[^:\s]+\z/)

          return version
        end

        # A private Replicate model may be pinned by a local training manifest,
        # or named in subject.env. Bare owner/name resolves the provider's latest
        # version at prediction time; MASTER records the prediction id/cost.
        model = subject_env["REPLICATE_MODEL"].to_s.strip
        return model if model.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/)

        raise "no trained Replicate version for #{@subject}; expected #{path} or REPLICATE_MODEL in #{@subject}/subject.env"
      rescue JSON::ParserError => error
        raise "invalid training manifest #{path}: #{error.message}"
      end

      # postpro writes its grade beside the still it was given.
      def grade(path, seed: nil)
        run_postpro(path, seed:)
        graded = Dir[graded_pattern(path)].max_by { |file| File.mtime(file) }
        raise "postpro succeeded but produced no graded still under #{File.dirname(path)}" unless graded

        graded
      end

      def run_postpro(path, seed: nil)
        script = File.join(ROOT, "postpro", "postpro.rb")
        # --heavy alone let every still draw one whisper-quiet chain: the first
        # selfie series came back looking ungraded. Heavy mode anchors each
        # take in a named look and deals the lane subtle to bleeding edge, so
        # the grade is a photographic decision, not a nudge.
        #
        # postpro deals those looks through Random.new(POSTPRO_SEED), so a seed
        # of nil re-rolls per run and two frames of one series can land on the
        # same look. A caller that wants each frame graded differently passes a
        # distinct seed; without one the environment decides, as before.
        env = seed ? { "POSTPRO_SEED" => seed.to_s } : {}
        stdout, stderr, status = Studio::Subprocess.capture3(
          env, RbConfig.ruby, script, "--heavy", "--count", "1", path, timeout: 600
        )
        return if status.success?

        raise "postpro failed: #{[stdout, stderr].compact.join("\n").lines.last.to_s.strip}"
      end

      # Where postpro names a one-take grade of `path`: beside it.
      def graded_pattern(path)
        ext = File.extname(path)
        stem = File.basename(path, ext).gsub(/[^0-9A-Za-z_-]+/, "_")
        File.join(File.dirname(path), "postpro_#{stem}_*_v1#{ext}")
      end

      def safe_stem(value)
        stem = value.to_s
        raise ArgumentError, "output name must be a simple filename stem" unless stem.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,100}\z/)

        stem
      end

      def first_url(output)
        case output
        when String then output
        when Array then output.compact.find { |item| item.is_a?(String) && item.start_with?("http") }
        when Hash then output["url"] || output["video"] || first_url(output.values)
        end || raise("prediction returned no file")
      end
    end
  end
end
