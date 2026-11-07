#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "tempfile"
require "tmpdir"
require "uri"

module Studio
  module MeretheLora
    SUBJECT_ROOT = File.expand_path(__dir__).freeze
    SOURCE_ROOT = File.join(SUBJECT_ROOT, "sources").freeze
    ADDITIONAL_ROOT = File.join(SOURCE_ROOT, "additional").freeze
    CACHE_ROOT = File.join(SUBJECT_ROOT, ".cache").freeze
    ZIP_PATH = File.join(CACHE_ROOT, "merethe_training.zip").freeze
    REPORT_PATH = File.join(CACHE_ROOT, "prepare_report.json").freeze

    # pub4 remains a read-only archival source. Recovery is pinned to the
    # historical commit and verifies each Git blob before retaining it locally.
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

    # Face-led, non-intimate starting frames reviewed from the archive.
    # Other originals are retained only in private sources/ and are not trained
    # by default because they lack a clear face, carry overlays or are intimate.
    CURATED_CAPTIONS = {
      "10.jpg" => "A close head-and-shoulders photograph of MERETHE, an adult woman with long wavy ash-blonde hair and blue eyes, wearing dark rectangular eyeglasses and a plain dark top, soft indoor light.",
      "11.jpg" => "A front-facing head-and-shoulders photograph of MERETHE, an adult woman with long wavy ash-blonde hair and blue eyes, without eyeglasses, wearing a plain dark top against a patterned indoor backdrop.",
      "12.jpg" => "A close indoor portrait photograph of MERETHE, an adult woman with long wavy ash-blonde hair and blue eyes, wearing dark rectangular eyeglasses and dark clothing, bright natural window light.",
      "13.jpg" => "A close portrait photograph of MERETHE, an adult woman with long wavy ash-blonde hair and blue eyes, looking slightly sideways, one hand resting against her cheek, wearing a dark top in soft indoor light."
    }.freeze

    class Error < StandardError; end

    module_function

    def recover!(source_root: SOURCE_ROOT)
      secure_directory(source_root)
      SOURCE_FILES.each do |filename, expected_sha|
        uri = URI("#{SOURCE_BASE_URL}/#{filename}")
        unless uri.is_a?(URI::HTTPS) && uri.host == "raw.githubusercontent.com"
          raise Error, "refusing unexpected source host"
        end

        body = fetch_bytes(uri, MAX_SOURCE_BYTES)
        actual_sha = git_blob_sha(body)
        unless actual_sha == expected_sha
          raise Error, "source verification failed for #{filename}: expected #{expected_sha}, got #{actual_sha}"
        end

        atomic_write(File.join(source_root, filename), body)
      end
      secure_directory(File.join(source_root, "additional"))
      { "status" => "RECOVERED", "source_count" => SOURCE_FILES.length, "source_commit" => SOURCE_COMMIT }
    end

    def prepare!(
      source_root: SOURCE_ROOT,
      additional_root: File.join(source_root, "additional"),
      cache_root: CACHE_ROOT,
      zip_path: File.join(cache_root, "merethe_training.zip"),
      report_path: File.join(cache_root, "prepare_report.json")
    )
      secure_directory(source_root)
      secure_directory(additional_root)
      secure_directory(cache_root)

      missing = CURATED_CAPTIONS.keys.reject { |name| verified_original?(name, source_root:) }
      additional, invalid = additional_images(additional_root:)
      candidate_count = CURATED_CAPTIONS.length + additional.length

      status = if missing.any?
                 "BLOCKED_MISSING_RECOVERED_SOURCES"
               elsif invalid.any?
                 "BLOCKED_INVALID_ADDITIONAL_IMAGES"
               elsif candidate_count < MIN_IMAGES
                 "BLOCKED_NEED_MORE_IMAGES"
               elsif candidate_count > MAX_IMAGES
                 "BLOCKED_TOO_MANY_IMAGES"
               else
                 "READY_FOR_OPERATOR_REVIEW"
               end

      report = {
        "status" => status,
        "source_commit" => SOURCE_COMMIT,
        "source_count" => SOURCE_FILES.length,
        "selected_archive_images" => CURATED_CAPTIONS.keys,
        "additional_captioned_images" => additional.map { |item| item[:name] },
        "candidate_count" => candidate_count,
        "minimum_images" => MIN_IMAGES,
        "recommended_range" => [TARGET_MIN_IMAGES, MAX_IMAGES],
        "missing_selected_sources" => missing,
        "problems" => invalid,
        "trainer" => TRAINER,
        "trainer_version" => TRAINER_VERSION,
        "trigger_word" => TRIGGER_WORD,
        "steps" => 1_000,
        "lora_rank" => 16,
        "training_started" => false,
        "provider_upload_started" => false
      }

      unless status == "READY_FOR_OPERATOR_REVIEW"
        write_report(report, cache_root:, report_path:)
        return report
      end

      Dir.mktmpdir("merethe-dataset-", cache_root) do |stage_root|
        build_dataset(additional, source_root:, stage_root:)
        zip_dataset!(stage_root:, cache_root:, zip_path:)
      end

      report["dataset_zip"] = zip_path
      write_report(report, cache_root:, report_path:)
      report
    rescue StandardError => error
      report = {
        "status" => "BLOCKED_PREPARATION_ERROR",
        "error" => "#{error.class}: #{error.message}",
        "training_started" => false,
        "provider_upload_started" => false
      }
      write_report(report, cache_root:, report_path:) rescue nil
      report
    end

    def verified_original?(filename, source_root: SOURCE_ROOT)
      path = File.join(source_root, filename)
      return false unless File.file?(path) && !File.symlink?(path)

      git_blob_sha(File.binread(path)) == SOURCE_FILES.fetch(filename)
    rescue SystemCallError
      false
    end

    def additional_images(additional_root: ADDITIONAL_ROOT)
      images = []
      problems = []
      secure_directory(additional_root)

      Dir.children(additional_root).sort.each do |name|
        extension = File.extname(name).downcase
        next unless IMAGE_EXTENSIONS.include?(extension)

        path = File.join(additional_root, name)
        unless File.file?(path) && !File.symlink?(path)
          problems << "#{name}: not a regular file"
          next
        end

        size = File.size(path)
        if size.zero? || size > MAX_ADDITIONAL_BYTES
          problems << "#{name}: image size must be 1..#{MAX_ADDITIONAL_BYTES} bytes"
          next
        end
        unless valid_image_file?(path, extension)
          problems << "#{name}: extension does not match a supported image signature"
          next
        end

        caption_path = File.join(additional_root, "#{File.basename(name, extension)}.txt")
        unless File.file?(caption_path) && !File.symlink?(caption_path)
          problems << "#{name}: missing same-basename .txt caption"
          next
        end
        if File.size(caption_path) > MAX_CAPTION_BYTES
          problems << "#{name}: caption exceeds #{MAX_CAPTION_BYTES} bytes"
          next
        end

        caption = File.read(caption_path, encoding: "UTF-8").strip
        unless caption.valid_encoding? && caption.match?(/\b#{Regexp.escape(TRIGGER_WORD)}\b/i)
          problems << "#{name}: caption must be valid UTF-8 and contain #{TRIGGER_WORD}"
          next
        end

        images << { name:, path:, caption:, size: }
      end

      [images, problems]
    end

    def valid_image_file?(path, extension)
      header = File.binread(path, 12)
      case extension
      when ".jpg", ".jpeg" then header.start_with?("\xFF\xD8\xFF".b)
      when ".png" then header.start_with?("\x89PNG\r\n\x1A\n".b)
      when ".webp" then header.byteslice(0, 4) == "RIFF" && header.byteslice(8, 4) == "WEBP"
      else false
      end
    rescue SystemCallError
      false
    end

    def build_dataset(additional, source_root:, stage_root:)
      CURATED_CAPTIONS.each do |filename, caption|
        copy_with_caption(File.join(source_root, filename), filename, caption, stage_root:)
      end
      additional.each do |item|
        destination_name = "additional_#{File.basename(item[:name])}"
        copy_with_caption(item[:path], destination_name, item[:caption], stage_root:)
      end
    end

    def copy_with_caption(source, filename, caption, stage_root:)
      unless caption.match?(/\b#{Regexp.escape(TRIGGER_WORD)}\b/i)
        raise Error, "caption for #{filename} must contain #{TRIGGER_WORD}"
      end

      destination = File.join(stage_root, filename)
      FileUtils.copy_file(source, destination)
      File.chmod(0o600, destination)
      atomic_write(
        File.join(stage_root, "#{File.basename(filename, File.extname(filename))}.txt"),
        "#{caption.strip}\n"
      )
    end

    def zip_dataset!(stage_root:, cache_root:, zip_path:)
      zip_executable = ENV.fetch("ZIP", "zip")
      Tempfile.create([".merethe-training-", ".zip"], cache_root) do |temporary|
        temporary.close
        File.unlink(temporary.path)
        stdout, stderr, status = Open3.capture3(
          zip_executable, "-q", "-X", "-r", temporary.path, ".", chdir: stage_root
        )
        unless status.success? && File.file?(temporary.path) && File.size(temporary.path).positive?
          raise Error, "zip command failed: #{[stdout, stderr].join(" ").strip}"
        end

        File.chmod(0o600, temporary.path)
        File.rename(temporary.path, zip_path)
      end
    rescue Errno::ENOENT
      raise Error, "zip executable not found; install the system zip utility"
    end

    def fetch_bytes(uri, maximum)
      body = +"".b
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) do |http|
        request = Net::HTTP::Get.new(uri.request_uri)
        http.request(request) do |response|
          raise Error, "source download returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
          raise Error, "source exceeds #{maximum} bytes" if response["content-length"].to_s.to_i > maximum

          response.read_body do |chunk|
            body << chunk
            raise Error, "source exceeds #{maximum} bytes" if body.bytesize > maximum
          end
        end
      end
      raise Error, "source download was empty" if body.empty?

      body
    end

    def git_blob_sha(bytes)
      Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0".b + bytes)
    end

    def secure_directory(path)
      raise Error, "refusing symlink directory: #{path}" if File.symlink?(path)

      FileUtils.mkdir_p(path, mode: 0o700)
      File.chmod(0o700, path)
    end

    def atomic_write(path, bytes)
      directory = File.dirname(path)
      Tempfile.create([".merethe-source-", ".part"], directory, binmode: true) do |temporary|
        temporary.write(bytes)
        temporary.flush
        temporary.fsync
        temporary.close
        File.rename(temporary.path, path)
      end
      File.chmod(0o600, path)
    end

    def write_report(report, cache_root:, report_path:)
      secure_directory(cache_root)
      atomic_write(report_path, JSON.pretty_generate(report) + "\n")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    arguments = ARGV.dup
    if arguments.delete("--help")
      puts "Usage: ruby #{File.basename(__FILE__)} [--recover]"
      puts "  --recover  retrieve and verify the 15 archived originals locally"
      puts "  default   build a private candidate ZIP only when 10-18 images are ready"
      exit 0
    end
    abort "unknown option: #{arguments.join(" ")}" unless arguments.empty? || arguments == ["--recover"]

    if arguments.delete("--recover")
      warn JSON.pretty_generate(Studio::MeretheLora.recover!)
    end

    report = Studio::MeretheLora.prepare!
    puts JSON.pretty_generate(report)
    exit(report["status"] == "READY_FOR_OPERATOR_REVIEW" ? 0 : 2)
  rescue Studio::MeretheLora::Error, SystemCallError, Net::HTTPError => error
    warn "BLOCKED: #{error.class}: #{error.message}"
    exit 2
  end
end
