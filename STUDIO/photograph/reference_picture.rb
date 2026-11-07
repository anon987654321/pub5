# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tempfile"
require "yaml"

require_relative "../output_paths"
require_relative "../replicate/client"

module Studio
  module Visual
    # A deliberately separate, reference-conditioned route. The existing
    # IdeaPicture LoRA route remains unchanged until this path is proven.
    class ReferencePicture
      MODEL = "qwen/qwen-image-edit-2511"
      MODEL_COST_ESTIMATE_USD = 0.03
      COST_REVIEWED_ON = "2026-11-07"
      MAX_REFERENCES = 3
      MAX_IMAGE_BYTES = 10 * 1024 * 1024
      MAX_PROMPT_BYTES = 2_000
      MAX_REFERENCE_PIXELS = 16_000_000
      ALLOWED_EXTENSIONS = %w[.jpg .jpeg .png .webp .gif].freeze
      DEFAULT_ROLES = {
        1 => %w[front],
        2 => %w[front three_quarter],
        3 => %w[front three_quarter expression]
      }.freeze
      REQUIRED_LOOK_FIELDS = %w[camera framing lighting color finish vfx avoid].freeze

      def initialize(
        subject:,
        client: nil,
        source_directory: nil,
        consent_path: nil,
        output_directory: nil,
        lookbook_path: nil
      )
        @subject = subject.to_s
        raise ArgumentError, "subject must be a simple directory name" unless @subject.match?(/\A[a-zA-Z0-9_-]+\z/)

        @subject_directory = File.join(File.dirname(__dir__), "replicate", "lora", @subject)
        @source_directory = source_directory || File.join(@subject_directory, "sources")
        @consent_path = consent_path || File.join(@subject_directory, "consent.yml")
        @output_directory = output_directory
        @lookbook_path = lookbook_path || File.join(__dir__, "lookbook.yml")
        @client = client
      end

      # This method has no provider or filesystem write side effects. It is
      # safe to use as the operator's preflight before any upload or charge.
      def preflight(prompt:, references:, look: "natural_selfie", reference_roles: nil,
                    seed: 42, cost_limit_usd:)
        prompt = prompt.to_s.strip
        raise ArgumentError, "prompt must contain 1..#{MAX_PROMPT_BYTES} bytes" if prompt.empty? || prompt.bytesize > MAX_PROMPT_BYTES

        seed = Integer(seed)
        raise ArgumentError, "seed must be between 0 and 2147483647" unless seed.between?(0, 2_147_483_647)

        cost_limit = Float(cost_limit_usd)
        raise ArgumentError, "cost limit must cover the current one-image estimate (USD #{format('%.2f', MODEL_COST_ESTIMATE_USD)})" if cost_limit < MODEL_COST_ESTIMATE_USD

        profile = load_look(look)
        consent = load_consent!
        files = validate_references(references)
        roles = Array(reference_roles || DEFAULT_ROLES.fetch(files.length))
        validate_roles!(roles, files.length)

        {
          state: "ready",
          model: MODEL,
          model_cost_estimate_usd: MODEL_COST_ESTIMATE_USD,
          cost_reviewed_on: COST_REVIEWED_ON,
          cost_limit_usd: cost_limit,
          subject: @subject,
          look: look.to_s,
          seed: seed,
          prompt: prompt,
          rendered_prompt: compose_prompt(prompt, profile),
          reference_roles: roles,
          references: files,
          consent_schema: consent.fetch("schema")
        }
      rescue TypeError, ArgumentError => error
        raise error
      end

      # Calling write is the explicit provider action. It uploads only after
      # the full local preflight passes, creates exactly one output, and keeps
      # the image and receipt in a private directory outside the checkout.
      def write(prompt:, references:, look: "natural_selfie", reference_roles: nil,
                seed: 42, cost_limit_usd:)
        plan = preflight(
          prompt:, references:, look:, reference_roles:, seed:, cost_limit_usd:
        )
        ensure_private_output_directory!

        uploaded = plan.fetch(:references).map { |item| client.upload_file(item.fetch(:path)) }
        prediction = client.run(
          MODEL,
          {
            prompt: plan.fetch(:rendered_prompt),
            image: uploaded,
            seed: plan.fetch(:seed),
            aspect_ratio: "match_input_image",
            go_fast: true,
            output_format: "webp",
            output_quality: 95
          },
          timeout: 600
        )

        url = first_url(prediction["output"])
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")
        image_path = File.join(output_directory, "#{@subject}_#{stamp}.webp")
        receipt_path = "#{image_path}.json"
        raise "output path already exists; refusing to overwrite: #{image_path}" if File.exist?(image_path) || File.exist?(receipt_path)

        client.download_url(url, image_path)
        File.chmod(0o600, image_path)
        receipt = build_receipt(plan, prediction, image_path)
        write_private_receipt(receipt_path, receipt)

        {
          "status" => "complete",
          "image" => image_path,
          "receipt" => receipt_path,
          "estimated_cost_usd" => MODEL_COST_ESTIMATE_USD,
          "model_version" => receipt["model_version"]
        }
      end

      private

      def client
        @client ||= Studio::ReplicateClient.new
      end

      def load_look(name)
        looks = YAML.safe_load(File.read(@lookbook_path), permitted_classes: [], aliases: false)
        profile = looks.fetch("looks").fetch(name.to_s)
        missing = REQUIRED_LOOK_FIELDS - profile.keys
        raise ArgumentError, "look #{name} is missing fields: #{missing.join(', ')}" unless missing.empty?

        profile
      rescue Errno::ENOENT
        raise "lookbook is missing: #{@lookbook_path}"
      rescue Psych::Exception, KeyError => error
        raise ArgumentError, "invalid photograph lookbook: #{error.message}"
      end

      def load_consent!
        stat = File.lstat(@consent_path)
        raise ArgumentError, "consent record must be a regular, non-symlink file" unless stat.file? && !stat.symlink?
        raise ArgumentError, "consent record must be owned by the current user" unless stat.uid == Process.uid
        raise ArgumentError, "consent record must be private (mode 0600)" unless (stat.mode & 0o077).zero?
        raise ArgumentError, "consent record is too large" if stat.size > 16_384

        value = YAML.safe_load(File.read(@consent_path), permitted_classes: [], aliases: false)
        raise ArgumentError, "consent record must be a mapping" unless value.is_a?(Hash)
        raise ArgumentError, "unsupported consent record schema" unless value["schema"] == 1
        raise ArgumentError, "consent record subject mismatch" unless value["subject"] == @subject

        person = value["subject_consent"]
        rights = value["source_rights"]
        unless person.is_a?(Hash) && person["likeness_generation"] == true && person["provider_processing"] == true
          raise ArgumentError, "subject consent for likeness generation and provider processing is not verified"
        end
        unless rights.is_a?(Hash) && rights["generation_use"] == true &&
               rights["provider_processing"] == true && rights["evidence"].to_s.strip.length >= 8
          raise ArgumentError, "source-image rights and provider processing evidence are not verified"
        end

        value
      rescue Errno::ENOENT
        raise ArgumentError, "missing private consent record: #{@consent_path}; copy photograph/consent.example.yml and complete it locally"
      rescue Psych::Exception => error
        raise ArgumentError, "invalid consent YAML: #{error.message}"
      end

      def validate_references(references)
        values = Array(references)
        raise ArgumentError, "provide 1..#{MAX_REFERENCES} reference images" unless values.length.between?(1, MAX_REFERENCES)

        root_stat = File.lstat(@source_directory)
        raise ArgumentError, "source directory must be a real directory, not a symlink" unless root_stat.directory? && !root_stat.symlink?
        root = File.realpath(@source_directory)
        raise ArgumentError, "source directory resolves unexpectedly" unless root == File.expand_path(@source_directory)

        files = values.map do |value|
          path = File.expand_path(value.to_s, root)
          stat = File.lstat(path)
          raise ArgumentError, "reference must be a regular, non-symlink file" unless stat.file? && !stat.symlink?
          real = File.realpath(path)
          raise ArgumentError, "reference escapes the subject sources directory" unless real.start_with?("#{root}#{File::SEPARATOR}")
          raise ArgumentError, "reference image is empty or over #{MAX_IMAGE_BYTES} bytes" unless stat.size.between?(1, MAX_IMAGE_BYTES)

          extension = File.extname(path).downcase
          raise ArgumentError, "unsupported reference format: #{extension}" unless ALLOWED_EXTENSIONS.include?(extension)
          header = File.binread(path, 16)
          validate_image_signature!(extension, header)

          {
            path: real,
            bytes: stat.size,
            sha256: Digest::SHA256.file(real).hexdigest
          }
        end

        hashes = files.map { |item| item.fetch(:sha256) }
        raise ArgumentError, "duplicate reference images are not useful; choose distinct views" unless hashes.uniq.length == hashes.length

        files
      rescue Errno::ENOENT => error
        raise ArgumentError, "reference or sources directory not found: #{error.message}"
      end

      def validate_image_signature!(extension, header)
        valid = case extension
                when ".jpg", ".jpeg" then header.start_with?("\xFF\xD8\xFF".b)
                when ".png" then header.start_with?("\x89PNG\r\n\x1A\n".b)
                when ".webp" then header.start_with?("RIFF".b) && header.byteslice(8, 4) == "WEBP"
                when ".gif" then header.start_with?("GIF87a".b) || header.start_with?("GIF89a".b)
                else false
                end
        raise ArgumentError, "file extension does not match a supported image signature" unless valid
      end

      def validate_roles!(roles, count)
        allowed = %w[front three_quarter expression other]
        raise ArgumentError, "reference role count must match image count" unless roles.length == count
        raise ArgumentError, "reference roles must be unique" unless roles.map(&:to_s).uniq.length == roles.length
        raise ArgumentError, "unsupported reference role" unless roles.all? { |role| allowed.include?(role.to_s) }
      end

      def compose_prompt(prompt, profile)
        [
          "Create one new, photorealistic photograph using the supplied images only as identity references.",
          "The references depict the same consenting adult. Preserve the person's recognisable facial identity and natural age: face shape, eye spacing, nose, mouth, jaw, hairline and distinctive features.",
          "Do not copy the exact pose, crop, expression, clothing or background of a reference unless the user's scene instruction asks for it. Do not beautify, de-age, stylise, slim, or alter facial structure.",
          "Keep real skin texture and believable fine detail. Eyes should be naturally focused, catchlights should match the scene, and facial anatomy must remain coherent.",
          "Scene and action: #{prompt}",
          "Camera and optics: #{profile.fetch('camera')}",
          "Framing and focus: #{profile.fetch('framing')}",
          "Lighting design: #{profile.fetch('lighting')}",
          "Color treatment: #{profile.fetch('color')}",
          "Photographic finish: #{profile.fetch('finish')}",
          "VFX and compositing realism: #{profile.fetch('vfx')}",
          "Avoid: #{profile.fetch('avoid')}",
          "No text, watermarks, logos, extra fingers, duplicated facial features, waxy skin, synthetic beauty retouching or arbitrary lens flares."
        ].join("\n")
      end

      def output_directory
        @output_directory ||
          Studio::OutputPaths.directory("photograph-renders", override: "STUDIO_PHOTOGRAPH_OUTPUT_DIR")
      end

      def ensure_private_output_directory!
        path = File.expand_path(output_directory)
        raise ArgumentError, "photograph output must remain outside the checkout" if Studio::OutputPaths.inside_repository?(path)

        created = !File.exist?(path)
        FileUtils.mkdir_p(path, mode: 0o700)
        File.chmod(0o700, path) if created

        stat = File.lstat(path)
        raise ArgumentError, "photograph output must not be a symlink" if stat.symlink?
        raise ArgumentError, "photograph output must be a directory" unless stat.directory?
        raise ArgumentError, "photograph output must be owned by the current user" unless stat.uid == Process.uid
        raise ArgumentError, "photograph output must be private (mode 0700)" unless (stat.mode & 0o077).zero?
      end

      def first_url(output)
        case output
        when String
          output if output.match?(/\Ahttps:\/\//)
        when Array
          output.each do |item|
            found = first_url(item)
            return found if found
          end
        when Hash
          output.each_value do |item|
            found = first_url(item)
            return found if found
          end
        end
      end

      def build_receipt(plan, prediction, image_path)
        {
          "schema" => 1,
          "status" => "complete",
          "created_at" => Time.now.utc.iso8601,
          "subject" => @subject,
          "model" => MODEL,
          "model_version" => prediction["version"],
          "prediction_id" => prediction["id"],
          "look" => plan.fetch(:look),
          "seed" => plan.fetch(:seed),
          "prompt" => plan.fetch(:prompt),
          "reference_roles" => plan.fetch(:reference_roles),
          "reference_sha256" => plan.fetch(:references).map { |item| item.fetch(:sha256) },
          "output_sha256" => Digest::SHA256.file(image_path).hexdigest,
          "estimated_cost_usd" => MODEL_COST_ESTIMATE_USD,
          "cost_estimate_reviewed_on" => COST_REVIEWED_ON,
          "provider_data_policy" => "Replicate model page states inputs and outputs are not used for training; re-check current terms before each production use."
        }
      end

      def write_private_receipt(path, value)
        Tempfile.create(["photograph-receipt-", ".json"], File.dirname(path), mode: 0o600) do |file|
          file.write(JSON.pretty_generate(value))
          file.write("\n")
          file.flush
          file.fsync
          File.chmod(0o600, file.path)
          file.close
          File.rename(file.path, path)
        end
      end
    end
  end
end
