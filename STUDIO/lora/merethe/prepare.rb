#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "tempfile"
require "uri"

module Studio
  module MeretheLora
    SUBJECT_ROOT = File.expand_path(__dir__).freeze
    # Move ignored subject data left at the former path; never follow symlinks
    # or overwrite a newer file in the canonical location.
    LEGACY_SUBJECT_ROOT = File.expand_path("../../replicate/lora/merethe", SUBJECT_ROOT).freeze
    LEGACY_DATA_ENTRIES = %w[sources dataset .cache weights out subject.env consent.yml].freeze
    SOURCE_ROOT = File.join(SUBJECT_ROOT, "sources").freeze
    ADDITIONAL_ROOT = File.join(SOURCE_ROOT, "additional").freeze
    DATASET_ROOT = File.join(SUBJECT_ROOT, "dataset").freeze
    CACHE_ROOT = File.join(SUBJECT_ROOT, ".cache").freeze
    ZIP_PATH = File.join(CACHE_ROOT, "merethe_training.zip").freeze
    REPORT_PATH = File.join(CACHE_ROOT, "prepare_report.json").freeze

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
      "15.jpg" => "b1a4ff18e8270a316f4db3838577fdf75fcf7093",
    }.freeze

    # Human-reviewed face-led starting subset. The other archived frames are
    # retained locally as originals but excluded from the general identity set:
    # low resolution, overlays/text, face obscured/cropped, or intimate framing.
    CURATED_CAPTIONS = {
      "10.jpg" => "A close head-and-shoulders photograph of MERETHE, an adult woman with long wavy ash-blonde hair and blue eyes, wearing dark rectangular eyeglasses and a plain dark top, soft indoor light.",
      "11.jpg" => "A front-facing head-and-shoulders photograph of MERETHE, an adult woman with long wavy ash-blonde hair and blue eyes, without eyeglasses, wearing a plain dark top against a patterned indoor backdrop.",
      "12.jpg" => "A close indoor portrait photograph of MERETHE, an adult woman with long wavy ash-blonde hair and blue eyes, wearing dark rectangular eyeglasses and dark clothing, bright natural window light.",
      "13.jpg" => "A close portrait photograph of MERETHE, an adult woman with long wavy ash-blonde hair and blue eyes, looking slightly sideways, one hand resting against her cheek, wearing a dark top in soft indoor light.",
    }.freeze

    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze

    class Error < StandardError; end

    module_function

    def recover!
      migrate_legacy_local_data!
      secure_directory(SOURCE_ROOT)
      SOURCE_FILES.each do |filename, expected_sha|
        uri = URI("#{SOURCE_BASE_URL}/#{filename}")
        raise Error, "refusing unexpected source host" unless uri.is_a?(URI::HTTPS) && uri.host == "raw.githubusercontent.com"

        body = fetch_bytes(uri, MAX_SOURCE_BYTES)
        actual_sha = git_blob_sha(body)
        raise Error, "source verification failed for #{filename}: expected #{expected_sha}, got #{actual_sha}" unless actual_sha == expected_sha

        atomic_write(File.join(SOURCE_ROOT, filename), body)
      end
      secure_directory(ADDITIONAL_ROOT)
      { "status" => "RECOVERED", "source_count" => SOURCE_FILES.length, "source_commit" => SOURCE_COMMIT }
    end

    def prepare!
      migrate_legacy_local_data!
      secure_directory(SOURCE_ROOT)
      secure_directory(CACHE_ROOT)

      missing = CURATED_CAPTIONS.keys.reject { |name| verified_original?(name) }
      additional, invalid = additional_images
      captions_missing = additional.select { |item| item[:caption].nil? || item[:caption].empty? }
      captions_missing.each { |item| invalid << "#{item[:name]}: missing .txt caption" }
      invalid.concat(additional.filter_map { |item| "#{item[:name]}: caption must contain #{TRIGGER_WORD}" unless item[:caption].to_s.match?(/\b#{Regexp.escape(TRIGGER_WORD)}\b/i) })

      candidate_count = CURATED_CAPTIONS.length + additional.length - captions_missing.length
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
        "steps" => 1000,
        "lora_rank" => 16,
        "training_started" => false,
        "provider_upload_started" => false
      }

      unless status == "READY_FOR_OPERATOR_REVIEW"
        write_report(report)
        return report
      end

      staging_root = Dir.mktmpdir("merethe-prepare-", CACHE_ROOT)
      staging_dataset = File.join(staging_root, "dataset")
      staging_zip = File.join(staging_root, "merethe_training.zip")
      build_dataset(additional, dataset_root: staging_dataset)
      zip_dataset!(dataset_root: staging_dataset, zip_path: staging_zip)
      publish_prepared_artifacts!(
        staged_dataset: staging_dataset,
        staged_zip: staging_zip,
        staging_root:
      )
      report["dataset_zip"] = ZIP_PATH
      report["status"] = "READY_FOR_OPERATOR_REVIEW"
      write_report(report)
      report
    rescue StandardError => error
      report = {
        "status" => "BLOCKED_PREPARATION_ERROR",
        "error" => "#{error.class}: #{error.message}",
        "training_started" => false,
        "provider_upload_started" => false
      }
      write_report(report) rescue nil
      report
    ensure
      FileUtils.remove_entry(staging_root) if staging_root && File.directory?(staging_root) && !File.symlink?(staging_root)
    end

    # Stage both artefacts on the same filesystem, retain the previous pair
    # until both new paths are in place, and roll back ordinary rename failures.
    # No failed validation/build is allowed to erase the last usable package.
    def publish_prepared_artifacts!(staged_dataset:, staged_zip:, staging_root:)
      unless File.directory?(staged_dataset) && !File.symlink?(staged_dataset) &&
             File.file?(staged_zip) && !File.symlink?(staged_zip) && File.size(staged_zip).positive?
        raise Error, "staged dataset and non-empty training ZIP are required"
      end

      if [DATASET_ROOT, ZIP_PATH].any? { |path| File.symlink?(path) }
        raise Error, "refusing to replace a symlinked prepared artifact"
      end
      if File.exist?(DATASET_ROOT) && !File.directory?(DATASET_ROOT)
        raise Error, "existing prepared dataset is not a directory"
      end
      if File.exist?(ZIP_PATH) && !File.file?(ZIP_PATH)
        raise Error, "existing training ZIP path is not a regular file"
      end

      backup_dataset = File.join(staging_root, "previous-dataset")
      backup_zip = File.join(staging_root, "previous-training.zip")
      previous_dataset = previous_zip = published_dataset = published_zip = false

      begin
        if File.exist?(DATASET_ROOT)
          File.rename(DATASET_ROOT, backup_dataset)
          previous_dataset = true
        end
        if File.exist?(ZIP_PATH)
          File.rename(ZIP_PATH, backup_zip)
          previous_zip = true
        end

        File.rename(staged_dataset, DATASET_ROOT)
        published_dataset = true
        File.rename(staged_zip, ZIP_PATH)
        published_zip = true
        File.chmod(0o700, DATASET_ROOT)
        File.chmod(0o600, ZIP_PATH)
      rescue StandardError
        FileUtils.remove_entry(DATASET_ROOT) if published_dataset && File.directory?(DATASET_ROOT) && !File.symlink?(DATASET_ROOT)
        FileUtils.rm_f(ZIP_PATH) if published_zip && File.file?(ZIP_PATH) && !File.symlink?(ZIP_PATH)
        File.rename(backup_dataset, DATASET_ROOT) if previous_dataset && File.exist?(backup_dataset)
        File.rename(backup_zip, ZIP_PATH) if previous_zip && File.exist?(backup_zip)
        raise
      end

      true
    end

    def migrate_legacy_local_data!
      return false unless File.directory?(LEGACY_SUBJECT_ROOT) && !File.symlink?(LEGACY_SUBJECT_ROOT)

      LEGACY_DATA_ENTRIES.each do |name|
        source = File.join(LEGACY_SUBJECT_ROOT, name)
        destination = File.join(SUBJECT_ROOT, name)
        next unless File.exist?(source) || File.symlink?(source)
        raise Error, "refusing legacy symlink: #{source}" if File.symlink?(source)
        raise Error, "legacy data and new data both exist: #{destination}" if File.exist?(destination) || File.symlink?(destination)
        raise Error, "legacy data is not a regular file or directory: #{source}" unless File.file?(source) || File.directory?(source)

        File.rename(source, destination)
      end
      true
    end

    def verified_original?(filename)
      path = File.join(SOURCE_ROOT, filename)
      return false unless File.file?(path) && !File.symlink?(path)

      git_blob_sha(File.binread(path)) == SOURCE_FILES.fetch(filename)
    rescue SystemCallError
      false
    end

    def additional_images
      secure_directory(ADDITIONAL_ROOT)
      images = Dir.children(ADDITIONAL_ROOT).sort.filter_map do |name|
        path = File.join(ADDITIONAL_ROOT, name)
        extension = File.extname(name).downcase
        next unless IMAGE_EXTENSIONS.include?(extension)
        next unless File.file?(path) && !File.symlink?(path)

        caption_path = File.join(ADDITIONAL_ROOT, "#{File.basename(name, File.extname(name))}.txt")
        caption = File.file?(caption_path) && !File.symlink?(caption_path) ? File.read(caption_path, encoding: "UTF-8").strip : nil
        { name: name, path: path, caption: caption, size: File.size(path) }
      end
      invalid = images.filter_map do |item|
        "#{item[:name]}: exceeds #{MAX_ADDITIONAL_BYTES} bytes" if item[:size] > MAX_ADDITIONAL_BYTES
      end
      [images.reject { |item| item[:size] > MAX_ADDITIONAL_BYTES }, invalid]
    end

    def build_dataset(additional, dataset_root: DATASET_ROOT)
      secure_directory(dataset_root)
      CURATED_CAPTIONS.each do |filename, caption|
        copy_with_caption(File.join(SOURCE_ROOT, filename), filename, caption, dataset_root:)
      end
      additional.each do |item|
        destination_name = "additional_#{File.basename(item[:name])}"
        copy_with_caption(item[:path], destination_name, item[:caption], dataset_root:)
      end
    end

    def copy_with_caption(source, filename, caption, dataset_root: DATASET_ROOT)
      raise Error, "caption for #{filename} must contain #{TRIGGER_WORD}" unless caption.match?(/\b#{Regexp.escape(TRIGGER_WORD)}\b/i)

      FileUtils.copy_file(source, File.join(dataset_root, filename))
      caption_path = File.join(dataset_root, "#{File.basename(filename, File.extname(filename))}.txt")
      File.write(caption_path, "#{caption.strip}\n", mode: "w", perm: 0o600)
      File.chmod(0o600, File.join(dataset_root, filename))
    end

    def zip_dataset!(dataset_root: DATASET_ROOT, zip_path: ZIP_PATH)
      zip_executable = ENV.fetch("ZIP", "zip")
      stdout, stderr, status = Open3.capture3(zip_executable, "-q", "-X", "-r", zip_path, ".", chdir: dataset_root)
      raise Error, "zip command unavailable or failed: #{[stdout, stderr].join(" ").strip}" unless status.success?
      raise Error, "training ZIP is missing or empty" unless File.file?(zip_path) && File.size(zip_path).positive?

      File.chmod(0o600, zip_path)
    rescue Errno::ENOENT
      raise Error, "zip executable not found; install the system zip utility"
    end

    def fetch_bytes(uri, maximum)
      body = +"".b
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) do |http|
        request = Net::HTTP::Get.new(uri.request_uri)
        http.request(request) do |response|
          raise Error, "source download returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
          declared = response["content-length"].to_s.to_i
          raise Error, "source exceeds #{maximum} bytes" if declared > maximum

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
      Tempfile.create([".merethe-source-", ".part"], directory, binmode: true) do |tempfile|
        tempfile.write(bytes)
        tempfile.flush
        tempfile.fsync
        tempfile.close
        File.rename(tempfile.path, path)
      end
      File.chmod(0o600, path)
    end

    def write_report(report)
      secure_directory(CACHE_ROOT)
      atomic_write(REPORT_PATH, JSON.pretty_generate(report) + "\n")
    end

    def inside_subject?(path)
      File.expand_path(path).start_with?("#{SUBJECT_ROOT}#{File::SEPARATOR}")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    arguments = ARGV.dup
    if arguments.delete("--help")
      puts "Usage: ruby #{File.basename(__FILE__)} [--recover]"
      puts "  --recover  retrieve and verify the 15 archived originals locally"
      puts "  default   build a private, captioned candidate ZIP only when 10-18 images are ready"
      exit 0
    end
    abort "unknown option: #{arguments.join(" ")}" unless arguments.empty? || arguments == ["--recover"]

    if arguments.delete("--recover")
      result = Studio::MeretheLora.recover!
      warn JSON.pretty_generate(result)
    end

    report = Studio::MeretheLora.prepare!
    puts JSON.pretty_generate(report)
    exit(report["status"] == "READY_FOR_OPERATOR_REVIEW" ? 0 : 2)
  rescue Studio::MeretheLora::Error, SystemCallError, Net::HTTPError => error
    warn "BLOCKED: #{error.class}: #{error.message}"
    exit 2
  end
end
