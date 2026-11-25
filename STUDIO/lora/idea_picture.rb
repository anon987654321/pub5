# frozen_string_literal: true

require "json"
require "digest"
require "tempfile"
require "yaml"
require "fileutils"
require "rbconfig"
require "securerandom"
require "uri"
require_relative "../replicate/output_paths"
require_relative "../replicate/client"
require_relative "../replicate/models"
require_relative "../replicate/subprocess"
require_relative "consent"
require_relative "../lora/lora"

module Studio
  module Visual
    # Bounds calls into the prediction client across a whole refinement batch,
    # including fallback engines. Provider-internal HTTP retries remain the
    # responsibility of the client.
    class PredictionBudget
      attr_reader :remaining, :limit

      def initialize(limit)
        @limit = Integer(limit)
        raise ArgumentError, "prediction budget must be between 1 and 8" unless @limit.between?(1, 8)
        @remaining = @limit
      end

      def exhausted? = remaining.zero?
      def used = limit - remaining

      def consume!
        raise ArgumentError, "prediction budget exhausted" if exhausted?

        @remaining -= 1
      end
    end

    class IdeaPicture
      # Highspeed is the default everyday 768P film engine. H3 Lite remains the
      # lower-cost drafting option at 480P or 768P; both accept 4-15 seconds.
      FILM = "minimax/h3-highspeed"
      # Which keys each film engine must accept, so a schema preflight can run
      # before any upload. Keys are the ones film_input actually sends.
      FILM_INPUT_KEYS = {
        "minimax/h3-lite" => %w[prompt first_frame_image duration resolution],
        "minimax/h3-highspeed" => %w[prompt first_frame_image duration],
        "kwaivgi/kling-v3-omni-video" => %w[prompt start_image duration mode generate_audio],
      }.freeze
      FILM_DEFAULT_KEYS = %w[prompt image duration mode aspect_ratio resolution].freeze
      REFERENCE_FALLBACK_LIMIT = 4
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

      # Reference photographs for a subject: an explicit references/ set wins;
      # otherwise fall back to the subject's own published sources. The fallback
      # keeps the reference route on by default without requiring a new flag.
      def self.reference_files(subject_directory)
        directory = File.expand_path(subject_directory.to_s)
        explicit = Dir[File.join(directory, "references", "*.{jpg,jpeg,png,webp}")]
                   .select { |path| File.file?(path) && !File.symlink?(path) }.sort
        return explicit unless explicit.empty?

        additional = Dir[File.join(directory, "sources", "additional", "*.{jpg,jpeg,png,webp}")]
                     .select { |path| File.file?(path) && !File.symlink?(path) }.sort
                     .first(REFERENCE_FALLBACK_LIMIT)
        archive = Dir[File.join(directory, "sources", "*.{jpg,jpeg,png,webp}")]
                  .select { |path| File.file?(path) && !File.symlink?(path) }.sort
                  .first(REFERENCE_FALLBACK_LIMIT)
        (additional + archive).uniq
      end

      def initialize(
        client: nil,
        directory: SUBJECTS,
        subject: ENV.fetch("STUDIO_PHOTOGRAPH_SUBJECT", "ragnhild"),
        model_manifest: nil,
        engine: nil,
        film_engine: nil,
        film_resolution: nil,
        subjects_root: SUBJECTS,
        lora_only: false,
        allow_unreviewed_likeness: false,
        inference_profile: nil
      )
        @client = client
        @directory = directory
        @subject = subject.to_s
        raise ArgumentError, "subject must be a simple directory name" unless @subject.match?(/\A[a-zA-Z0-9_-]+\z/)

        # Subject data defaults to the checkout's own private lora tree; tests
        # inject a subjects_root rather than writing into that tree.
        @subject_directory = File.join(subjects_root, @subject)
        @model_manifest = model_manifest || default_model_manifest
        @engine = engine&.to_s
        raise ArgumentError, "inference profiles apply only to the subject's pinned LoRA route" if @engine && !inference_profile.nil?
        @lora_only = !!lora_only
        raise ArgumentError, "inference profiles apply only to the subject's pinned LoRA route" if !inference_profile.nil? && !@lora_only
        @allow_unreviewed_likeness = !!allow_unreviewed_likeness
        raise ArgumentError, "lora_only cannot be combined with a different engine" if @lora_only && @engine
        raise ArgumentError, "unreviewed likeness is available only for the LoRA candidate-review path" if @allow_unreviewed_likeness && !@lora_only
        @film_engine = film_engine&.to_s
        @film_resolution = film_resolution&.to_s
        configured_profiles = Studio::ReplicateClient::TRAINING_STANDARDS.fetch("inference").fetch("profiles")
        @inference_profile = (inference_profile || Studio::ReplicateClient::TRAINING_STANDARDS.fetch("inference").fetch("profile")).to_s
        raise ArgumentError, "unknown inference profile #{@inference_profile.inspect}; choose #{configured_profiles.keys.join(", ")}" unless configured_profiles.key?(@inference_profile)
      end

      def inference_profile
        return unless @lora_only

        @inference_profile || Studio::ReplicateClient::TRAINING_STANDARDS.fetch("inference").fetch("profile")
      end

      def write(words, film: true, duration: 5, output_stem: nil, grade_seed: nil, preset: nil, compiled: false, prediction_budget: nil)
        lint_prompt!(words)
        if preset && !Studio::Lora::Craft::LABORATORY.include?(preset)
          raise ArgumentError, "unknown laboratory preset"
        end
        unless grade_seed.nil?
          grade_seed = Integer(grade_seed)
          raise ArgumentError, "grade seed out of range" unless grade_seed.between?(0, 2_147_483_647)
        end
        validate_model!
        if film
          validate_film_model!
          film_resolution if film_engine == "minimax/h3-lite"
        end
        FileUtils.mkdir_p(@directory)
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")
        default_stem = preset ? "#{@subject}_selfie_shot" : @subject
        stem = [safe_stem(output_stem || default_stem), stamp, SecureRandom.hex(3)].join("_")
        @compiled_capture = compiled
        @prediction_budget = prediction_budget
        @capture_receipt = nil
        @last_capture_model = @last_capture_input = nil
        grade_seed ||= SecureRandom.random_number(2_147_483_647) if preset
        still = render_still(words, stem, grade_seed:, preset:)
        result = { "still" => still }
        result["capture"] = @capture_receipt if @capture_receipt
        @compiled_capture = false
        result["clip"] = render_film(words, still, stem, duration) if film
        result
      ensure
        @compiled_capture = false
        @prediction_budget = nil
      end

      # Explicit structured shots use the same inference and consent boundary
      # as free-form requests. The compiled prompt already owns camera geometry.
      def write_shot(shot, grade_seed: nil, prediction_budget: nil)
        plan = Studio::Lora::Craft.compile_shot(shot)
        result = write(plan.fetch("prompt"), film: false, output_stem: "#{@subject}_selfie_shot",
                       grade_seed:, preset: plan.fetch("preset"), compiled: true, prediction_budget:)
        result.merge("plan" => plan)
      ensure
        @compiled_capture = false
      end

      # Animate an existing LoRA still; never regenerate or overwrite its source.
      def animate(still, words, duration: 5)
        authorize_subject!
        lint_prompt!(words)
        source = File.expand_path(still.to_s)
        raise ArgumentError, "source still is missing" unless File.file?(source) && !File.symlink?(source)
        raise ArgumentError, "source still must be jpg, png or webp" unless %w[.jpg .jpeg .png .webp].include?(File.extname(source).downcase)
        raise ArgumentError, "source still exceeds 25 MB" if File.size(source) > 25 * 1024 * 1024
        require_private_media_file!(source)

        seconds = Integer(duration)
        raise ArgumentError, "duration must be between 1 and 10 seconds" unless seconds.between?(1, 10)

        validate_film_model!
        FileUtils.mkdir_p(@directory)
        stamp = "#{safe_stem(@subject)}_film_#{Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")}_#{SecureRandom.hex(3)}"
        { "still" => source, "clip" => render_film(words, source, stamp, seconds) }
      end

      def validate_model!
        authorize_subject!
        # In LoRA-only mode a missing manifest or incompatible schema is a hard
        # preflight failure. A subject selfie must never fall back to a generic face.
        # A selected reference engine is validated against its own schema, not
        # against the subject's LoRA (the two do not share FLUX input keys).
        model = engine
        lora = @lora_only || model == "$subject_lora"
        model = still_model if model == "$subject_lora"
        if @lora_only
          reviewed_version = subject_env["LIKELINESS_REVIEWED_VERSION"].to_s.strip
          unless reviewed_version == model
            unless @allow_unreviewed_likeness && candidate_review_directory?
              raise "LoRA likeness is not approved for #{@subject}: compare full-size training samples with approved subject references, then set LIKELINESS_REVIEWED_VERSION to the exact pinned version in private subject.env (#{model})"
            end
          end
        end
        return model if @validated_still_model == model

        names = client.input_names(model).map(&:to_s)
        raise "Replicate model is unavailable or has no readable input schema: #{model}" if names.empty?

        required = lora ? %w[prompt model num_inference_steps guidance_scale] : %w[prompt]
        missing = required - names
        if missing.any?
          label = lora ? "FLUX inference inputs" : "still inputs"
          raise "Replicate model #{model} is missing required #{label}: #{missing.join(", ")}"
        end

        @validated_still_inputs = names.freeze
        @validated_still_model = model
        model
      end

      def lora_configured?
        still_model
        true
      rescue StandardError
        false
      end

      def validate_film_model!
        return film_engine if @validated_film_model

        names = client.input_names(film_engine)
        raise "Replicate film model is unavailable or has no readable input schema: #{film_engine}" if names.empty?

        missing = film_input_keys - names
        raise "Replicate film model #{film_engine} is missing inputs used by the animation renderer: #{missing.join(", ")}" unless missing.empty?

        @validated_film_model = film_engine
        film_engine
      end

      # The film engine in use: the class default, or the one --film-engine
      # selected. It stays a catalogue name so the preflight above can check the
      # model's own schema before any upload.
      def film_engine
        @film_engine || FILM
      end

      # The input keys the selected film engine is required to accept. H3 Lite
      # takes a first frame plus a prompt; Kling v3 Omni takes start_image; the
      # remaining fallback models take an `image`.
      def film_input_keys
        FILM_INPUT_KEYS.fetch(film_engine, FILM_DEFAULT_KEYS)
      end

      # Lite defaults to its cheapest 480P output; callers may select 768P.
      # Highspeed is fixed at 768P and does not accept a resolution input.
      def film_resolution
        return unless film_engine == "minimax/h3-lite"

        resolution = (@film_resolution || "480P").upcase
        raise ArgumentError, "H3 Lite resolution must be 480P or 768P" unless %w[480P 768P].include?(resolution)

        resolution
      end

      # Lay a music bed under a rendered clip. The clip keeps its own video and
      # is re-encoded with the audio track; the silent original is left in place
      # and the muxed file is written beside it with an `_audio` suffix, so the
      # provider output is never overwritten. `audio` must be a readable local
      # path or a URL ffmpeg can open.
      def add_soundtrack(clip, audio)
        source = File.expand_path(clip.to_s)
        raise ArgumentError, "clip is missing: #{source}" unless File.file?(source) && !File.symlink?(source)
        raise ArgumentError, "audio source is missing: #{audio}" if audio.to_s.empty?
        raise "ffmpeg is not on PATH" unless ffmpeg?

        path = source.sub(/(\.mp4)\z/i, "_audio\\1")
        path = "#{source}_audio.mp4" if path == source
        raise "refusing to replace an existing film: #{path}" if File.exist?(path) || File.symlink?(path)

        _out, err, status = Studio::Subprocess.capture3(
          "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
          "-i", source, "-i", audio.to_s,
          "-map", "0:v:0", "-map", "1:a:0",
          "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
          "-shortest", "-movflags", "+faststart", path,
          timeout: 300
        )
        raise "ffmpeg failed to lay the soundtrack: #{err}" unless status.success? && File.file?(path)

        File.chmod(0o600, path)
        path
      end

      # Expose only the validated private descriptor needed by the local
      # training orchestrator. Action-scoped consent is checked again here;
      # credentials never belong in subject.env.
      def subject_configuration(action: :generation)
        Studio::Lora::Consent.require!(
          subject: @subject, subject_directory: @subject_directory, action:
        )
        subject_env.dup.freeze
      end

      private

      # Candidate rendering is a narrow exception for likeness review, not
      # a general bypass: output must stay below this subject's private cache.
      def candidate_review_directory?
        base = File.expand_path(@subject_directory)
        root = File.join(base, ".cache", "likeness-review")
        target = File.expand_path(@directory)
        return false unless target.start_with?("#{root}#{File::SEPARATOR}")

        paths = [base, File.join(base, ".cache"), root]
        cursor = root
        target.delete_prefix("#{root}#{File::SEPARATOR}").split(File::SEPARATOR).each do |part|
          cursor = File.join(cursor, part)
          paths << cursor
        end
        paths.each do |path|
          stat = File.lstat(path)
          return false unless stat.directory? && !stat.symlink? && stat.uid == Process.uid && (stat.mode & 0o077).zero?
        end
        true
      rescue SystemCallError
        false
      end
      private :candidate_review_directory?

      def authorize_subject!
        Studio::Lora::Consent.require!(
          subject: @subject, subject_directory: @subject_directory, action: :generation
        )
      end

      def client
        @client ||= Studio::ReplicateClient.new
      end

      def require_private_media_file!(path)
        stat = File.lstat(path)
        raise ArgumentError, "subject media must be a regular non-symlink file" unless stat.file? && !stat.symlink?
        raise ArgumentError, "subject media must be owned by the current user" unless stat.uid == Process.uid
        raise ArgumentError, "subject media must be owner-only (0600)" unless (stat.mode & 0o077).zero?
        raise ArgumentError, "subject media must not be hard-linked" unless stat.nlink == 1
        true
      rescue SystemCallError => error
        raise ArgumentError, "cannot verify private subject media: #{error.class}: #{error.message}"
      end

      # Prompt-optimiser vocabulary ("8k", "masterpiece", "flawless") pulls a
      # render toward concept art and retouched, poreless skin - the exact
      # failures the craft vocabulary exists to avoid. Refuse before any
      # provider call: a paid render from a self-defeating prompt is waste,
      # and silently rewriting the words would hide the mistake
      # (FAIL_VISIBLY). The word list and its reasons live in
      # Studio::Lora::Craft::BACKFIRING_WORDS.
      def lint_prompt!(words)
        hits = Studio::Lora::Craft.backfiring_words(words)
        return if hits.empty?

        reasons = hits.map { |word, why| "#{word} (#{why})" }.join("; ")
        raise ArgumentError, "prompt works against itself: #{reasons}"
      end

      def render_still(words, stem, grade_seed: nil, preset: nil)
        base_path = File.join(@directory, safe_stem(stem))
        existing = %w[.png .jpg .jpeg .webp].map { |extension| "#{base_path}#{extension}" }
                                              .find { |candidate| File.exist?(candidate) || File.symlink?(candidate) }
        raise "refusing to replace an existing still: #{existing}" if existing

        output = render_with_fallback(words)
        path = "#{base_path}#{still_extension(output)}"
        raise "refusing to replace an existing still: #{path}" if File.exist?(path) || File.symlink?(path)

        client.download_url(first_url(output), path)
        File.chmod(0o600, path)
        graded = preset ? grade(path, seed: grade_seed, preset:) : grade(path, seed: grade_seed)
        File.chmod(0o600, graded)
        if preset
          @capture_receipt = {
            "schema" => "studio.capture.v1", "model" => @last_capture_model,
            "input" => @last_capture_input, "original" => path, "grade" => graded,
            "original_sha256" => Digest::SHA256.file(path).hexdigest,
            "grade_sha256" => Digest::SHA256.file(graded).hexdigest,
            "preset" => preset, "grade_seed" => grade_seed, "review" => "NOT_REVIEWED"
          }
          # Postpro already owns the grade sidecar. Record capture provenance
          # beside the ungraded original without modifying the lab receipt.
          write_capture_receipt(path, @capture_receipt)
        end
        # The provider original and its grade are separate project assets.
        # Keep both; grading must never destroy the original still.
        graded
      end

      def write_capture_receipt(path, receipt)
        destination = "#{path}.json"
        Tempfile.create([".capture-", ".json"], File.dirname(path), mode: 0o600) do |file|
          file.write(JSON.pretty_generate(receipt) + "\n")
          file.flush
          File.link(file.path, destination)
        end
      end

      # STUDIO must render on Replicate, and must not stop for want of a credit.
      # Try the chosen engine, then the catalogue's fallback chain, which ends in
      # Replicate's free tier. Each engine gets the input shape it declares; a
      # reference model is handed the subject's own photographs, a text model
      # only the prompt, and the subject's LoRA its trained version.
      def render_with_fallback(words, timeout: 600)
        chain = render_chain
        failures = []
        chain.each_with_index do |candidate, index|
          @prediction_budget&.consume!
          model = resolve_engine(candidate)
          begin
            input = still_input(words, candidate)
            output = client.predict(model, input, timeout:)
            @last_capture_model = model
            # Never persist uploaded reference URLs, tokens, or arbitrary provider inputs.
            allowed = %w[prompt model aspect_ratio resolution size num_inference_steps guidance_scale guidance lora_scale seed go_fast output_format output_quality]
            @last_capture_input = input.transform_keys(&:to_s).select { |key, value| allowed.include?(key) && (value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false) }
            return output
          rescue StandardError => error
            failures << "#{candidate} (#{error.message})"
            warn "STUDIO: #{candidate} failed, falling back" unless index == chain.length - 1
          end
        end

        raise "every engine failed: #{failures.join('; ')}"
      end

      # The chain to try, with the reference engines removed when the subject has
      # no reference photographs — otherwise every render would spend three
      # failures before reaching an engine that can actually run.
      def render_chain
        return ["$subject_lora"] if engine == "$subject_lora"

        chain = Studio::ReplicateClient::Models.chain_for(engine)
        return chain if references_available?

        chain.reject { |name| reference_engine?(name) }
      end

      def reference_engine?(name)
        Studio::ReplicateClient::Models.engines.dig(name, "likeness") == "reference"
      end

      def references_available? = reference_files.any?

      def resolve_engine(name)
        name == "$subject_lora" ? still_model : name
      end

      # The engine this render reaches for first: the catalogue's default
      # reference model when the subject has reference photographs, otherwise
      # the pinned subject LoRA. An explicit engine is an override.
      def engine
        return "$subject_lora" if @lora_only
        return @engine if @engine
        return Studio::ReplicateClient::Models.default_engine if references_available?
        return "$subject_lora" if lora_configured?

        Studio::ReplicateClient::Models.default_engine
      end

      public :engine

      # The input for one engine, shaped to what that engine declares.
      def still_input(words, engine_name = nil)
        engine_name ||= engine
        spec = Studio::ReplicateClient::Models.engines[engine_name]
        case
        when engine_name == "$subject_lora" then lora_input(words)
        when spec && spec["likeness"] == "reference" then reference_input(words, engine_name)
        else text_input(words, engine_name)
        end
      end

      # The subject's trained LoRA: one named profile supplies all three
      # inference controls. A/B reviews can vary the profile without changing
      # scene text, model version, seed, output format or post-production.
      def lora_input(words)
        settings = Studio::ReplicateClient::TRAINING_STANDARDS.fetch("inference")
        profile = settings.fetch("profiles").fetch(inference_profile)
        desired = {
          prompt: photographic(words),
          model: settings.fetch("model"),
          num_inference_steps: profile.fetch("num_inference_steps"),
          guidance_scale: profile.fetch("guidance_scale"),
        }
        optional = {
          aspect_ratio: settings["aspect_ratio"],
          num_outputs: settings["num_outputs"],
          output_format: settings["output_format"],
          output_quality: settings["output_quality"],
          go_fast: settings["go_fast"],
          lora_scale: profile.fetch("lora_scale"),
          seed: settings["seed"],
        }
        allowed = Array(@validated_still_inputs).map(&:to_s)
        optional.each do |key, value|
          desired[key] = value if !value.nil? && allowed.include?(key.to_s)
        end
        desired
      end

      # A reference model keeps the face from the subject's own photographs. Send
      # only the keys the model declares (models.yml), so a model with `images`
      # rather than `image_input`, or without output_quality, gets a schema it
      # accepts.
      def reference_input(words, engine_name = engine)
        allowed = Studio::ReplicateClient::Models.inputs_for(engine_name).map(&:to_s)
        desired = { "prompt" => photographic(words), "aspect_ratio" => "2:3" }
        desired["image_input"] = reference_urls if allowed.include?("image_input")
        desired["images"] = reference_urls if allowed.include?("images")
        desired["input_images"] = reference_urls if allowed.include?("input_images")
        desired["input_image"] = primary_reference_url if allowed.include?("input_image")
        desired["subject_reference"] = primary_reference_url if allowed.include?("subject_reference")
        desired["max_images"] = 1 if allowed.include?("max_images")
        desired["number_of_images"] = 1 if allowed.include?("number_of_images")
        desired["prompt_optimizer"] = !@compiled_capture if allowed.include?("prompt_optimizer")
        sizing = output_sizing(engine_name)
        desired["resolution"] = sizing if allowed.include?("resolution")
        desired["size"] = sizing if allowed.include?("size")
        desired["output_format"] = "jpg" if allowed.include?("output_format")
        desired["output_quality"] = 95 if allowed.include?("output_quality")
        desired
      end

      # Each provider names its output size in its own vocabulary, and a value
      # from another provider's schema fails the prediction. 2K is the studio
      # target; flux-2-flex counts megapixels instead (2048px cap, 2 MP
      # recommended by its own schema).
      def output_sizing(engine_name)
        engine_name == "black-forest-labs/flux-2-flex" ? "2 MP" : "2K"
      end

      # A text model has only the prompt; the descriptor carries what likeness it
      # can. This is the free tier, reached only when the better engines failed.
      def text_input(words, engine_name = engine)
        desired = {
          "prompt" => photographic(words),
          "aspect_ratio" => "2:3",
          "num_outputs" => 1,
          "guidance" => 3.5,
          "num_inference_steps" => 28,
          "output_format" => "jpg",
          "output_quality" => 95,
          "go_fast" => true,
        }
        allowed = Studio::ReplicateClient::Models.inputs_for(engine_name).map(&:to_s)
        desired.select { |key, _| allowed.include?(key) }
      end

      # The subject's own reference photographs, uploaded once and reused for
      # every frame of a series. Required, because a reference engine with no
      # references is a text prompt wearing a likeness model's name — the raise
      # here sends the render on to the next engine in the chain instead.
      # MiniMax Image-01 takes one face reference; upload only the first
      # reviewed source image instead of sending the full reference set.
      def primary_reference_url
        @primary_reference_url ||= begin
          source = reference_files.first
          raise "no reference photographs for #{@subject} in #{references_directory}" unless source

          client.upload_file(source, subject: @subject)
        end
      end

      def reference_urls
        @reference_urls ||= reference_files.map { |file| client.upload_file(file, subject: @subject) }.tap do |urls|
          raise "no reference photographs for #{@subject} in #{references_directory}" if urls.empty?
        end
      end

      def reference_files
        self.class.reference_files(@subject_directory)
      end

      def references_directory = File.join(@subject_directory, "references")

      def render_film(words, still, stamp, duration)
        path = File.join(@directory, "#{safe_stem(stamp)}.mp4")
        receipt_path = "#{path}.json"
        raise "refusing to replace an existing film: #{path}" if File.exist?(path) || File.symlink?(path)
        raise "refusing to replace an existing film receipt: #{receipt_path}" if File.exist?(receipt_path) || File.symlink?(receipt_path)

        input = film_input(words, still, duration)
        prediction = if client.respond_to?(:predict_with_receipt)
                       client.predict_with_receipt(film_engine, input, timeout: 600)
                     else
                       { "output" => client.predict(film_engine, input, timeout: 600), "receipt" => nil }
                     end
        client.download_url(first_url(prediction.fetch("output")), path)
        raise "film download did not produce a regular file" unless File.file?(path) && !File.symlink?(path)

        File.chmod(0o600, path)
        write_film_receipt(path, still, duration, prediction["receipt"])
        path
      end

      def write_film_receipt(path, still, duration, provider_receipt)
        receipt_path = "#{path}.json"
        receipt = {
          "schema" => "studio.film_render.v1",
          "created_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
          "subject" => @subject,
          "model" => film_engine,
          "requested_duration_seconds" => duration,
          "source_still_sha256" => Digest::SHA256.file(still).hexdigest,
          "output_video_sha256" => Digest::SHA256.file(path).hexdigest,
          "output_bytes" => File.size(path),
          "provider_prediction" => provider_receipt || {
            "status" => "NOT_CAPTURED",
            "actual_cost_usd" => nil,
            "actual_cost_status" => "NOT_REPORTED",
          },
          # A film is judged in motion, watched in full: a beautiful first
          # frame proves nothing about the last one. Every temporal axis stays
          # NOT_REVIEWED until a person has watched the whole clip.
          "human_review" => {
            "visual" => "NOT_REVIEWED",
            "likeness" => "NOT_REVIEWED",
            "temporal" => {
              "watched_in_full" => "NOT_REVIEWED",
              "identity_stability" => "NOT_REVIEWED",
              "no_melt_or_morph" => "NOT_REVIEWED",
              "motion_plausibility" => "NOT_REVIEWED",
              "camera_restraint" => "NOT_REVIEWED",
              "light_coherence" => "NOT_REVIEWED",
            },
          }
        }
        Tempfile.create([".film-receipt-", ".json"], File.dirname(receipt_path), mode: 0o600) do |file|
          file.write(JSON.pretty_generate(receipt) + 10.chr)
          file.flush
          file.fsync
          file.close
          File.link(file.path, receipt_path)
        end
        File.chmod(0o600, receipt_path)
        receipt
      end

      def ffmpeg?
        @ffmpeg_checked ||= begin
          _, _, status = Studio::Subprocess.capture3("ffmpeg", "-version", timeout: 30)
          status.success?
        rescue StandardError
          false
        end
      end

      def film_input(words, still, duration)
        prompt = "The same photograph, held, one slow motion. #{words}"
        case film_engine
        when "minimax/h3-lite", "minimax/h3-highspeed"
          # Both H3 engines take first_frame_image; Lite additionally requires
          # its selectable output resolution. Image-to-video inherits the
          # still's aspect ratio.
          resolution = film_resolution if film_engine == "minimax/h3-lite"
          seconds = h3_duration(duration)
          input = {
            prompt:,
            first_frame_image: client.upload_file(still, subject: @subject),
            duration: seconds,
          }
          input[:resolution] = resolution if resolution
          return input
        when "kwaivgi/kling-v3-omni-video"
          # Kling v3 Omni takes start_image, and its duration window is 3-15s.
          # Native audio stays off: STUDIO lays the dilla bed under the cut in
          # add_soundtrack, so a provider track would fight it.
          return {
            prompt:,
            start_image: client.upload_file(still, subject: @subject),
            duration: kling_duration(duration),
            mode: "pro",
            generate_audio: false,
          }
        end

        {
          prompt:,
          image: client.upload_file(still, subject: @subject),
          duration:,
          mode: "quality",
          aspect_ratio: "2:3",
          resolution: "768p",
        }
      end

      # Both H3 models accept 4-15s; the renderer's own 1-10s range would fail
      # below 4, so clamp up to the shared model floor.
      def h3_duration(seconds)
        seconds = Integer(seconds)
        seconds.clamp(4, 15)
      end

      # Kling v3 Omni accepts 3-15s.
      def kling_duration(seconds)
        Integer(seconds).clamp(3, 15)
      end

      # The subject trigger is a field in the small schema-1 plan.
      def training_trigger
        path = File.join(@subject_directory, "train.yaml")
        return nil unless File.file?(path) && !File.symlink?(path)
        raise "training plan exceeds 1 MB" if File.size(path) > 1_048_576

        plan = YAML.safe_load(File.read(path, encoding: "UTF-8"),
                              permitted_classes: [], permitted_symbols: [], aliases: false)
        return nil unless plan.is_a?(Hash) && plan["schema"] == 1 && plan["subject"] == @subject

        trigger = plan["trigger_word"].to_s
        trigger if trigger.match?(/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/)
      rescue Psych::Exception => error
        raise "invalid subject training plan #{path}: #{error.message}"
      end

      def photographic(words)
        env = subject_env
        trigger = env["TRIGGER"].to_s.strip
        trigger = training_trigger if trigger.empty?
        capture = @compiled_capture ? words : Studio::Lora::Craft.photographic(words)
        [trigger, env["DESCRIPTOR"], capture].compact.reject(&:empty?).join(", ")
      end

      # subject.env is a private operator record, never a second secret store.
      # Refuse public permissions, symlinks, hard links, foreign ownership,
      # unknown fields and duplicate keys before using any prompt material.
      def subject_env
        path = File.join(@subject_directory, "subject.env")
        return {} unless File.exist?(path) || File.symlink?(path)

        stat = File.lstat(path)
        raise "subject.env must be a regular, non-symlink file" unless stat.file? && !stat.symlink?
        raise "subject.env must be owned by the current user" unless stat.uid == Process.uid
        raise "subject.env must be owner-only (0600)" unless (stat.mode & 0o077).zero?
        raise "subject.env must not be hard-linked" unless stat.nlink == 1
        raise "subject.env exceeds 64 KB" if stat.size > 65_536

        allowed = %w[SUBJECT MODEL TRIGGER DESCRIPTOR REPLICATE_DESTINATION REPLICATE_MODEL LIKELINESS_REVIEWED_VERSION]
        File.foreach(path).each_with_object({}) do |line, env|
          stripped = line.strip
          next if stripped.empty? || stripped.start_with?("#")

          match = /\A([A-Z][A-Z0-9_]*)=(.*)\z/.match(stripped)
          raise "subject.env contains an invalid line" unless match

          key, value = match.captures
          raise "subject.env contains a secret field" if key.match?(/TOKEN|API_KEY|SECRET|PASSWORD|CREDENTIAL/i)
          raise "subject.env contains an unsupported field: #{key}" unless allowed.include?(key)
          raise "subject.env repeats #{key}" if env.key?(key)

          value = value.strip
          value = value[1...-1] if value.length >= 2 && value.start_with?('"') && value.end_with?('"')
          env[key] = value
        end
      end

      # The tracked root manifest is the public, non-secret pin. A local
      # weights/<model>/ manifest takes precedence when the operator has
      # migrated a subject-specific private checkpoint.
      def default_model_manifest
        configured = subject_env["MODEL"].to_s.strip
        configured = @subject if configured.empty?
        raise ArgumentError, "MODEL in #{@subject}/subject.env must be a simple directory name" unless configured.match?(/\A[a-zA-Z0-9_.-]+\z/)

        private_manifest = File.join(@subject_directory, "weights", configured, "replicate_training.json")
        tracked_manifest = File.join(@subject_directory, "replicate_training.json")
        return private_manifest if File.file?(private_manifest) && !File.symlink?(private_manifest)

        # An explicit immutable private pin supersedes a historical tracked
        # checkpoint. A newly trained local weights manifest remains first.
        configured_version = subject_env["REPLICATE_MODEL"].to_s.strip
        if configured_version.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}:[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/)
          return private_manifest
        end
        return tracked_manifest if File.file?(tracked_manifest) && !File.symlink?(tracked_manifest)

        private_manifest
      end

      # A manifest under weights/ is a private subject artifact. The old
      # subject-root manifest is tracked compatibility metadata and remains
      # readable; private manifests must stay inside owner-only directories.
      def require_private_training_manifest!(path)
        subject_root = File.expand_path(@subject_directory)
        weights_root = File.join(subject_root, "weights")
        absolute = File.expand_path(path)
        return true unless absolute.start_with?("#{weights_root}#{File::SEPARATOR}")

        model_directory = File.dirname(absolute)
        unless File.dirname(model_directory) == weights_root &&
               File.basename(absolute) == "replicate_training.json"
          raise "private training manifest must be weights/<model>/replicate_training.json"
        end

        [subject_root, weights_root, model_directory].each do |directory|
          stat = File.lstat(directory)
          unless stat.directory? && !stat.symlink? &&
                 stat.uid == Process.uid && (stat.mode & 0o077).zero?
            raise "private training manifest directory must be current-user-owned and owner-only (0700): #{directory}"
          end
        end

        stat = File.lstat(absolute)
        unless stat.file? && !stat.symlink? &&
               stat.uid == Process.uid && stat.nlink == 1 &&
               (stat.mode & 0o077).zero?
          raise "private training manifest must be a regular, current-user-owned, singly-linked owner-only (0600) file: #{absolute}"
        end
        true
      rescue SystemCallError => error
        raise "cannot verify private training manifest: #{error.class}: #{error.message}"
      end

      def still_model
        path = @model_manifest
        raise "training manifest must not be a symlink: #{path}" if File.symlink?(path)
        if File.file?(path)
          require_private_training_manifest!(path)
          raise "training manifest exceeds 64 KB: #{path}" if File.size(path) > 65_536
          version = JSON.parse(File.read(path, encoding: "UTF-8"))["version"].to_s
          raise "training manifest has no valid owner/model:version: #{path}" unless version.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}:[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/)

          return version
        end

        # Training destinations are not inference pins. Predictions require an
        # immutable owner/model:version from the private manifest or REPLICATE_MODEL.
        model = subject_env["REPLICATE_MODEL"].to_s.strip
        return model if model.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}:[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/)

        raise "no trained, pinned Replicate version for #{@subject}; expected #{path} or owner/model:version in #{@subject}/subject.env"
      rescue JSON::ParserError => error
        raise "invalid training manifest #{path}: #{error.message}"
      end

      # Honour the provider's actual media suffix. When a signed URL has no
      # useful suffix, LoRA masters default to the configured lossless format.
      def still_extension(output)
        url = first_url(output)
        extension = File.extname(URI.parse(url).path).downcase
        return extension if %w[.png .jpg .jpeg .webp].include?(extension)

        format = @lora_only ? Studio::ReplicateClient::TRAINING_STANDARDS.fetch("inference").fetch("output_format") : "jpg"
        ".#{format}"
      rescue URI::InvalidURIError
        format = @lora_only ? Studio::ReplicateClient::TRAINING_STANDARDS.fetch("inference").fetch("output_format") : "jpg"
        ".#{format}"
      end

      # postpro writes its grade beside the still it was given.
      def grade(path, seed: nil, preset: nil)
        return grade_named(path, preset, seed:) if preset

        run_postpro(path, seed:)
        graded = Dir[graded_pattern(path)].max_by { |file| File.mtime(file) }
        raise "postpro succeeded but produced no graded still under #{File.dirname(path)}" unless graded
        raise "postpro grade is a symlink or not a regular file" unless File.file?(graded) && !File.symlink?(graded)

        File.chmod(0o600, graded)
        graded
      end

      def grade_named(path, preset, seed: nil)
        script = File.join(ROOT, "postpro", "postpro.rb")
        extension = File.extname(path)
        stem = File.basename(path, extension)
        output = File.join(File.dirname(path), "postpro_#{stem}_#{preset}_v1#{extension}")
        raise "refusing to replace an existing grade" if File.exist?(output) || File.symlink?(output)
        env = seed ? { "POSTPRO_SEED" => seed.to_s } : {}
        stdout, stderr, status = Studio::Subprocess.capture3(
          env, RbConfig.ruby, script, "--input", path, "--output", output, "--preset", preset, timeout: 600
        )
        raise "postpro failed: #{[stdout, stderr].compact.join("\n").lines.last.to_s.strip}" unless status.success?
        raise "postpro produced no regular grade" unless File.file?(output) && !File.symlink?(output)

        File.chmod(0o600, output)
        sidecar = "#{output}.json"
        File.chmod(0o600, sidecar) if File.file?(sidecar) && !File.symlink?(sidecar)
        output
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
