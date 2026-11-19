#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require_relative "consent"

module Studio
  module Lora
    # Copies approved local subject material from a read-only pub4 checkout.
    # Dry-run is the default. It never copies datasets, loose weights, renders,
    # credentials, or consent records; consent remains local and subject-owned.
    class LocalMigration
      REPO_ROOT = File.expand_path("../..", __dir__).freeze
      DESTINATION_ROOT = File.join(REPO_ROOT, "STUDIO", "lora").freeze
      SOURCE_ROOTS = %w[
        STUDIO/replicate/lora
        STUDIO/lora
        studio/lora
        studio/lora/training
      ].freeze
      SUBJECTS = %w[johann ragnhild merethe].freeze
      IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze
      MAX_FILE_BYTES = 50 * 1024 * 1024

      JOHANN_HISTORY_COMMIT = "4c0211c821954003998593d147629e8716c09ded".freeze
      JOHANN_HISTORY_FILES = {
        "20240627_000251.jpg" => "08cf030b763a919a71bd4dc19aa1da48313faa89",
        "20240705_161331.jpg" => "1db28036f6397d1a2f30da8d38385e1ab85e976b",
        "20260725_015451.jpg" => "cac622e9a061181a99738074909f4ef639ee35d2"
      }.freeze

      class Error < StandardError; end

      def self.run(argv)
        options = {
          source: File.expand_path("../../../pub4", __dir__),
          subject: nil, apply: false, include_sources: false,
          restore_johann_history: false
        }
        OptionParser.new do |parser|
          parser.banner = "Usage: ruby STUDIO/lora/migrate_local.rb [options]"
          parser.on("--from PATH", "read-only local pub4 checkout (default: ../pub4)") { |value| options[:source] = File.expand_path(value) }
          parser.on("--subject NAME", "migrate one subject only") { |value| options[:subject] = value }
          parser.on("--include-sources", "include existing sources/ and references/ after rights preflight") { options[:include_sources] = true }
          parser.on("--restore-johann-history", "include three hash-verified Johann originals from Git history") { options[:restore_johann_history] = true }
          parser.on("--apply", "copy approved local files; default is read-only dry-run") { options[:apply] = true }
          parser.on("-h", "--help", "show this help") { puts parser; return { "status" => "help" } }
        end.parse!(argv)

        raise Error, "unexpected arguments: #{argv.join(" ")}" unless argv.empty?
        raise Error, "invalid subject name" if options[:subject] && !SUBJECTS.include?(options[:subject])
        raise Error, "--restore-johann-history applies only to Johann" if options[:restore_johann_history] && options[:subject] && options[:subject] != "johann"

        source = File.expand_path(options[:source])
        raise Error, "source checkout does not exist: #{source}" unless File.directory?(source)
        raise Error, "source checkout must contain .git" unless File.exist?(File.join(source, ".git"))

        names = options[:subject] ? [options[:subject]] : SUBJECTS
        reports = names.map { |name| new(source_checkout: source, **options.reject { |key, _| key == :source || key == :subject }).migrate(name) }
        {
          "schema" => "studio.lora.local_migration.v1",
          "status" => reports.any? { |report| report["status"] == "BLOCKED" } ? "BLOCKED" : "REVIEW",
          "mode" => options[:apply] ? "apply" : "dry_run",
          "source_checkout" => source,
          "source_read_only" => true,
          "provider_calls" => 0,
          "subjects" => reports
        }
      end

      def initialize(source_checkout:, destination_root: DESTINATION_ROOT, apply: false, include_sources: false, restore_johann_history: false)
        @source_checkout = File.expand_path(source_checkout)
        @destination_root = File.expand_path(destination_root)
        @apply = apply
        @include_sources = include_sources
        @restore_johann_history = restore_johann_history
      end

      def migrate(subject)
        destination = File.join(@destination_root, subject)
        candidates = SOURCE_ROOTS.map { |root| File.join(@source_checkout, root, subject) }
                                 .select { |path| File.directory?(path) && !File.symlink?(path) }
        entries = candidates.flat_map { |root| planned_entries(root) }
        entries.concat(johann_history_entries) if subject == "johann" && @restore_johann_history
        entries = deduplicate(entries)

        if entries.empty?
          return { "subject" => subject, "status" => "NO_SOURCE", "copied" => [] }
        end

        conflicts = entries.filter_map do |entry|
          target = File.join(destination, entry.fetch(:relative))
          entry.fetch(:relative) if File.exist?(target) || File.symlink?(target)
        end
        unless conflicts.empty?
          return {
            "subject" => subject, "status" => "BLOCKED",
            "reason" => "destination already contains files; refusing to overwrite",
            "conflicts" => conflicts
          }
        end

        required_sources = required_source_sets(entries)
        if @apply
          raise Error, "destination subject directory is a symlink" if File.symlink?(destination)
          raise Error, "destination subject directory must already exist with its private consent record" unless File.directory?(destination)
          File.chmod(0o700, destination)
          consent = Consent.validate(
            subject:, subject_directory: destination,
            required_sources: (Consent.required_source_sets(subject:, subject_directory: destination) + required_sources).uniq,
            action: :generation
          )
          unless consent.fetch("valid")
            return {
              "subject" => subject, "status" => "BLOCKED",
              "reason" => "private generation consent and source-rights evidence are incomplete",
              "errors" => consent.fetch("errors")
            }
          end
          copied = apply_entries(destination, entries)
          {
            "subject" => subject, "status" => "COPIED",
            "legacy_directories" => candidates.map { |path| path.delete_prefix("#{@source_checkout}/") },
            "required_source_sets" => required_sources,
            "copied" => copied
          }
        else
          {
            "subject" => subject, "status" => "REVIEW",
            "legacy_directories" => candidates.map { |path| path.delete_prefix("#{@source_checkout}/") },
            "required_source_sets" => required_sources,
            "planned" => entries.map { |entry| { "path" => entry.fetch(:relative), "bytes" => entry.fetch(:bytes), "sha256" => entry.fetch(:sha256) } },
            "note" => "No files copied. Apply requires a valid private consent.yml and separate rights evidence."
          }
        end
      rescue Error, SystemCallError, IOError => error
        { "subject" => subject, "status" => "BLOCKED", "reason" => "#{error.class}: #{error.message}" }
      end

      private

      def planned_entries(root)
        entries = []
        env = File.join(root, "subject.env")
        env = File.join(root, "ai_toolkit", "subject.env") unless File.file?(env)
        reject_symlink_components!(root, env) if File.exist?(env) || File.symlink?(env)
        entries << entry(env, "subject.env") if File.file?(env)

        weights_root = File.join(root, "weights")
        raise Error, "refusing symlink weights directory: #{weights_root}" if File.symlink?(weights_root)
        if File.directory?(weights_root)
          Dir.children(weights_root).sort.each do |model|
            model_root = File.join(weights_root, model)
            raise Error, "refusing symlink model directory: #{model_root}" if File.symlink?(model_root)
            next unless File.directory?(model_root)

            manifest = File.join(model_root, "replicate_training.json")
            reject_symlink_components!(root, manifest) if File.exist?(manifest) || File.symlink?(manifest)
            entries << entry(manifest, File.join("weights", model, "replicate_training.json")) if File.file?(manifest)
          end
        end

        if @include_sources
          %w[sources references].each do |name|
            directory = File.join(root, name)
            walk_files(directory).each do |path|
              relative = Pathname.new(path).relative_path_from(Pathname.new(directory)).to_s
              entries << entry(path, File.join(name, relative))
            end
          end
        end
        entries
      end

      def walk_files(directory)
        return [] unless File.directory?(directory) && !File.symlink?(directory)

        Dir.glob(File.join(directory, "**", "*"), File::FNM_DOTMATCH).sort.filter_map do |path|
          next if %w[. ..].include?(File.basename(path))

          stat = File.lstat(path)
          raise Error, "refusing symlink in local source tree: #{path}" if stat.symlink?
          next if stat.directory?
          raise Error, "unsupported source entry: #{path}" unless stat.file?
          raise Error, "source file exceeds #{MAX_FILE_BYTES} bytes: #{path}" if stat.size > MAX_FILE_BYTES
          raise Error, "source file is not owned by the current user: #{path}" unless stat.uid == Process.uid
          raise Error, "source file is hard-linked: #{path}" unless stat.nlink == 1

          path
        end
      end

      def reject_symlink_components!(root, path)
        base = File.realpath(root)
        expanded = File.expand_path(path)
        raise Error, "source path escapes the subject directory: #{path}" unless expanded.start_with?("#{base}#{File::SEPARATOR}")

        cursor = base
        expanded.delete_prefix("#{base}#{File::SEPARATOR}").split(File::SEPARATOR).each do |part|
          cursor = File.join(cursor, part)
          raise Error, "refusing symlink in source path: #{cursor}" if File.symlink?(cursor)
        end
      end

      def entry(source, relative)
        stat = File.lstat(source)
        raise Error, "legacy input is not a regular file: #{source}" unless stat.file? && !stat.symlink?
        raise Error, "legacy input is not owned by the current user: #{source}" unless stat.uid == Process.uid
        raise Error, "legacy input exceeds #{MAX_FILE_BYTES} bytes: #{source}" if stat.size > MAX_FILE_BYTES

        { source:, relative:, bytes: stat.size, sha256: Digest::SHA256.file(source).hexdigest }
      end

      def johann_history_entries
        JOHANN_HISTORY_FILES.map do |filename, expected_sha|
          source_path = "STUDIO/lora/johann/sources/#{filename}"
          revision = "#{JOHANN_HISTORY_COMMIT}:#{source_path}"
          bytes, error, status = Open3.capture3("git", "-C", @source_checkout, "show", revision, binmode: true)
          raise Error, "cannot recover #{source_path} from read-only Git history: #{error.strip}" unless status.success?

          actual = Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0".b + bytes)
          raise Error, "historical Git blob hash mismatch for #{filename}" unless actual == expected_sha

          {
            bytes:, sha256: Digest::SHA256.hexdigest(bytes),
            relative: File.join("sources", "archive", filename),
            history_bytes: bytes
          }
        end
      end

      def deduplicate(entries)
        indexed = {}
        entries.each do |item|
          path = item.fetch(:relative)
          if indexed.key?(path)
            raise Error, "legacy sources disagree at #{path}; compare them locally before migration" unless indexed.fetch(path).fetch(:sha256) == item.fetch(:sha256)
          else
            indexed[path] = item
          end
        end
        indexed.values
      end

      def required_source_sets(entries)
        sets = []
        entries.each do |entry|
          path = entry.fetch(:relative)
          if path.start_with?("references/")
            sets << "reference_photographs"
          elsif path.start_with?("sources/")
            sets << "subject_sources"
          end
        end
        sets.uniq
      end

      def prepare_destination_parent!(parent, destination)
        root = File.realpath(destination)
        expanded = File.expand_path(parent)
        return if expanded == root
        raise Error, "destination path escapes the subject directory" unless expanded.start_with?("#{root}#{File::SEPARATOR}")

        cursor = root
        expanded.delete_prefix("#{root}#{File::SEPARATOR}").split(File::SEPARATOR).each do |part|
          cursor = File.join(cursor, part)
          raise Error, "refusing symlink in destination path: #{cursor}" if File.symlink?(cursor)
          if File.exist?(cursor)
            raise Error, "destination parent is not a directory: #{cursor}" unless File.directory?(cursor)
          else
            Dir.mkdir(cursor, 0o700)
          end
          File.chmod(0o700, cursor)
        end
      end

      def apply_entries(destination, entries)
        created = []
        begin
          entries.each do |item|
            target = File.join(destination, item.fetch(:relative))
            raise Error, "destination already exists: #{item.fetch(:relative)}" if File.exist?(target) || File.symlink?(target)

            parent = File.dirname(target)
            prepare_destination_parent!(parent, destination)
            File.open(target, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
              if item[:history_bytes]
                output.write(item.fetch(:history_bytes))
              else
                File.open(item.fetch(:source), "rb") { |input| IO.copy_stream(input, output) }
              end
              output.flush
              output.fsync
            end
            File.chmod(0o600, target)
            created << target
          end
        rescue StandardError
          created.reverse_each { |path| File.delete(path) if File.file?(path) && !File.symlink?(path) }
          raise
        end
        created.map do |path|
          { "path" => path.delete_prefix("#{destination}/"), "bytes" => File.size(path), "mode" => "0600" }
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    puts JSON.pretty_generate(Studio::Lora::LocalMigration.run(ARGV))
  rescue Studio::Lora::LocalMigration::Error, OptionParser::ParseError, SystemCallError => error
    warn "BLOCKED: #{error.class}: #{error.message}"
    exit 2
  end
end
