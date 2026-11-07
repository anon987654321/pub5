# frozen_string_literal: true

require "digest"
require "json"
require "uri"

module Studio
  # Private Merethe dataset preparation. Every external effect crosses the
  # injected Core::World: file reads/writes, source retrieval, and ZIP creation.
  module MeretheLora
    SOURCE_ROOT = "studio/replicate/lora/merethe/sources".freeze
    ADDITIONAL_ROOT = "#{SOURCE_ROOT}/additional".freeze
    ADDITIONAL_MANIFEST = "#{SOURCE_ROOT}/additional.json".freeze
    DATASET_ROOT = "studio/replicate/lora/merethe/dataset".freeze
    CACHE_ROOT = "studio/replicate/lora/merethe/.cache".freeze
    REPORT_PATH = "#{CACHE_ROOT}/prepare_report.json".freeze

    SOURCE_COMMIT = "8e1955ae130592ab7c20ee266c024f061431c67e".freeze
    SOURCE_BASE_URL = "https://raw.githubusercontent.com/anon987654321/pub4/#{SOURCE_COMMIT}/media/__lora/me2".freeze
    TRAINER = "ostris/flux-dev-lora-trainer".freeze
    TRAINER_VERSION = "26dce37af90b9d997eeb970d92e47de3064d46c300504ae376c75bef6a9022d2".freeze
    TRIGGER_WORD = "MERETHE".freeze

    MIN_IMAGES = 10
    TARGET_MIN_IMAGES = 12
    MAX_IMAGES = 18
    MAX_SOURCE_BYTES = 25 * 1024 * 1024
    MAX_ADDITIONAL_BYTES = 20 * 1024 * 1024
    MAX_CAPTION_BYTES = 4_096
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze

    SOURCE_FILES = {
      "01.jpg" => "5f90e252dd8c688eba0ca6c7a7c41325e0adc238",
      "02.jpg" => "4d62ef0cd99cf9fdb1ce74d2e9abd2818794e65f",
      "03.jpg" => "8a9212955bed3227153841ad76978968311c780a",
      "04.jpg" => "d5f36ec8ba10b3d422081f3726f6cfdc22079f53",
      "05.jpg" => "02ab505076a6faceb873bafc7bd3c0a557af16e4",
      "06.jpg" => "2673c0120500074d20d9a21fae939b4371d94b9d",
      "07.jpg" => "62721b5dc5b1dbb61bdb2adebebc68a64aa7acff",
      "08.jpg" => "0c40c96e47e227fed4fe7fe7c35ff6994ac22351",
      "09.jpg" => "c1f5aba5bf892e67d0b027ff9e10892ae0adcc8a",
      "10.jpg" => "65463211e6be34dc904f698079fac68a6e9cc35c",
      "11.jpg" => "d385e7b6b6b1374bf4184f803e6ea211a930053d",
      "12.jpg" => "7bafc38f5e95a51086441defff3fd90a791a369c",
      "13.jpg" => "41f036fdefb4b0b6c8842ad629f39512af85e418",
      "14.jpg" => "41092f65d522ff52745fbd4b3d14df2a3606a2b1",
      "15.jpg" => "b1a4ff18e8270a316f4db3838577fdf75fcf7093"
    }.freeze

    CURATED_CAPTIONS = {
      "10.jpg" => "A close head-and-shoulders photograph of MERETHE, an adult woman with long wavy ash-blonde hair and blue eyes, wearing dark rectangular eyeglasses and a plain dark top, soft indoor light.",
      "11.jpg" => "A front-facing head-and-shoulders photograph of MERETHE, an adult woman with long wavy ash-blonde hair and blue eyes, without eyeglasses, wearing a plain dark top against a patterned indoor backdrop.",
      "12.jpg" => "A close indoor portrait photograph of MERETHE, an adult woman with long wavy ash-blonde hair and blue eyes, wearing dark rectangular eyeglasses and dark clothing, bright natural window light.",
      "13.jpg" => "A close portrait photograph of MERETHE, an adult woman with long wavy ash-blonde hair and blue eyes, looking slightly sideways, one hand resting against her cheek, wearing a dark top in soft indoor light."
    }.freeze

    class Error < StandardError; end

    module_function

    # Recover the 15 historical originals through Core::World. pub4 is used
    # strictly as a read-only source; all writes land under pub5's ignored paths.
    def recover!(world:)
      SOURCE_FILES.each do |filename, expected_sha|
        url = "#{SOURCE_BASE_URL}/#{filename}"
        uri = URI(url)
        raise Error, "refusing unexpected source URL" unless uri.is_a?(URI::HTTPS) && uri.host == "raw.githubusercontent.com"

        reply = world.net(:get, url)
        raise Error, "source download returned HTTP #{reply.status} for #{filename}" unless reply.status == 200

        bytes = reply.body.to_s.b
        raise Error, "source exceeds #{MAX_SOURCE_BYTES} bytes: #{filename}" if bytes.bytesize > MAX_SOURCE_BYTES
        actual_sha = git_blob_sha(bytes)
        raise Error, "source verification failed for #{filename}" unless actual_sha == expected_sha

        world.write("#{SOURCE_ROOT}/#{filename}", bytes, mode: 0o600)
      end

      world.write("#{SOURCE_ROOT}/recovery.json",
                  JSON.pretty_generate("source_commit" => SOURCE_COMMIT, "source_count" => SOURCE_FILES.size) + "\n",
                  mode: 0o600)
      { "status" => "RECOVERED", "source_count" => SOURCE_FILES.size, "source_commit" => SOURCE_COMMIT }
    end

    # additional.json is local and ignored. It is a list of
    # {"file":"photo-01.jpg","caption":"MERETHE, ..."} records. Its named
    # images live in sources/additional/. No directory traversal is required.
    def prepare!(world:)
      missing = CURATED_CAPTIONS.keys.reject { |name| verified_original?(world:, filename: name) }
      additional, problems = additional_images(world:)
      count = CURATED_CAPTIONS.length + additional.length

      status = if missing.any?
                 "BLOCKED_MISSING_RECOVERED_SOURCES"
               elsif problems.any?
                 "BLOCKED_INVALID_ADDITIONAL_IMAGES"
               elsif count < MIN_IMAGES
                 "BLOCKED_NEED_MORE_IMAGES"
               elsif count > MAX_IMAGES
                 "BLOCKED_TOO_MANY_IMAGES"
               else
                 "READY_FOR_OPERATOR_REVIEW"
               end

      report = {
        "status" => status,
        "source_commit" => SOURCE_COMMIT,
        "source_count" => SOURCE_FILES.size,
        "selected_archive_images" => CURATED_CAPTIONS.keys,
        "additional_captioned_images" => additional.map { |item| item[:file] },
        "candidate_count" => count,
        "minimum_images" => MIN_IMAGES,
        "target_range" => [TARGET_MIN_IMAGES, MAX_IMAGES],
        "missing_selected_sources" => missing,
        "problems" => problems,
        "trainer" => TRAINER,
        "trainer_version" => TRAINER_VERSION,
        "trigger_word" => TRIGGER_WORD,
        "steps" => 1_000,
        "lora_rank" => 16,
        "provider_upload_started" => false,
        "training_started" => false
      }

      if status == "READY_FOR_OPERATOR_REVIEW"
        entries = curated_entries(world:) + additional
        fingerprint = dataset_fingerprint(entries)
        dataset_path = "#{DATASET_ROOT}/#{fingerprint[0, 16]}"
        entries.each do |entry|
          world.write("#{dataset_path}/#{entry[:file]}", entry[:bytes], mode: 0o600)
          caption_name = entry[:file].sub(/\.[^.]+\z/, ".txt")
          world.write("#{dataset_path}/#{caption_name}", "#{entry[:caption]}\n", mode: 0o600)
        end

        zip_path = "#{CACHE_ROOT}/merethe_training_#{fingerprint[0, 16]}.zip"
        absolute_zip = "#{world.manifest.root}/#{zip_path}"
        absolute_dataset = "#{world.manifest.root}/#{dataset_path}"
        run = world.exec("zip", "-q", "-X", "-r", absolute_zip, ".", chdir: absolute_dataset)
        raise Error, "ZIP creation failed: #{run.err}" unless run.ok?

        report["dataset_fingerprint"] = fingerprint
        report["dataset_zip"] = zip_path
      end

      world.write(REPORT_PATH, JSON.pretty_generate(report) + "\n", mode: 0o600)
      report
    rescue StandardError => error
      report = {
        "status" => "BLOCKED_PREPARATION_ERROR",
        "error" => "#{error.class}: #{error.message}",
        "provider_upload_started" => false,
        "training_started" => false
      }
      world.write(REPORT_PATH, JSON.pretty_generate(report) + "\n", mode: 0o600)
      report
    end

    def verified_original?(world:, filename:)
      expected_sha = SOURCE_FILES.fetch(filename)
      bytes = world.read("#{SOURCE_ROOT}/#{filename}").to_s.b
      git_blob_sha(bytes) == expected_sha
    rescue Errno::ENOENT
      false
    end

    def additional_images(world:)
      document = JSON.parse(world.read(ADDITIONAL_MANIFEST))
      raise Error, "additional.json must contain an array" unless document.is_a?(Array)

      images = []
      problems = []
      document.each do |record|
        unless record.is_a?(Hash) && record.keys.sort == %w[caption file]
          problems << "each additional record must contain exactly file and caption"
          next
        end

        filename = record["file"].to_s
        unless filename.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,120}\.(?:jpe?g|png|webp)\z/i)
          problems << "invalid additional image filename: #{filename.inspect}"
          next
        end

        extension = filename[filename.rindex(".")..].downcase
        unless IMAGE_EXTENSIONS.include?(extension)
          problems << "unsupported image extension: #{filename}"
          next
        end

        caption = record["caption"].to_s.strip
        unless caption.bytesize <= MAX_CAPTION_BYTES && caption.valid_encoding? &&
               caption.match?(/\b#{Regexp.escape(TRIGGER_WORD)}\b/i)
          problems << "#{filename}: caption must be valid UTF-8, <= #{MAX_CAPTION_BYTES} bytes and contain #{TRIGGER_WORD}"
          next
        end

        begin
          bytes = world.read("#{ADDITIONAL_ROOT}/#{filename}").to_s.b
        rescue Errno::ENOENT
          problems << "#{filename}: image file is missing"
          next
        end
        if bytes.empty? || bytes.bytesize > MAX_ADDITIONAL_BYTES || !valid_image?(bytes, extension)
          problems << "#{filename}: image is empty, too large or has an invalid signature"
          next
        end

        images << { file: filename, caption:, bytes: }
      end

      [images, problems]
    rescue Errno::ENOENT
      [[], []]
    rescue JSON::ParserError => error
      [[], ["additional.json is invalid JSON: #{error.message}"]]
    end

    def valid_image?(bytes, extension)
      case extension
      when ".jpg", ".jpeg" then bytes.start_with?("\xFF\xD8\xFF".b)
      when ".png" then bytes.start_with?("\x89PNG\r\n\x1A\n".b)
      when ".webp" then bytes.byteslice(0, 4) == "RIFF" && bytes.byteslice(8, 4) == "WEBP"
      else false
      end
    end

    def curated_entries(world:)
      CURATED_CAPTIONS.map do |filename, caption|
        { file: filename, caption:, bytes: world.read("#{SOURCE_ROOT}/#{filename}").to_s.b }
      end
    end

    def dataset_fingerprint(entries)
      digest = Digest::SHA256.new
      entries.sort_by { |entry| entry[:file] }.each do |entry|
        digest.update(entry[:file])
        digest.update("\0")
        digest.update(entry[:bytes])
        digest.update("\0")
        digest.update(entry[:caption])
        digest.update("\0")
      end
      digest.hexdigest
    end

    def git_blob_sha(bytes)
      Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0".b + bytes)
    end
  end
end
