#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "digest"
require "open3"
require "json"
require "optparse"
require "pathname"
require "yaml"

module Studio
  module LoraLocalMigration
    REPO_ROOT = File.expand_path("../../..", __dir__).freeze
    DESTINATION_ROOT = File.join(REPO_ROOT, "STUDIO", "replicate", "lora").freeze
    SOURCE_ROOTS = %w[
      STUDIO/replicate/lora
      STUDIO/lora
      studio/lora
      studio/lora/training
    ].freeze
    SUBJECT_NAME = /\A[a-zA-Z0-9_-]+\z/.freeze

    class Error < StandardError; end

    module_function

    def run(argv)
      options = {
        source: File.expand_path("../../../../pub4", __dir__),
        subject: nil,
        apply: false,
        include_sources: false,
        restore_johann_history: false
      }
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby STUDIO/replicate/lora/migrate_local.rb [options]"
        parser.on("--from PATH", "read-only legacy pub4 checkout (default: ../pub4)") { |value| options[:source] = File.expand_path(value) }
        parser.on("--subject NAME", "migrate one subject only") { |value| options[:subject] = value }
        parser.on("--include-sources", "include existing local private source photographs; requires valid destination consent") { options[:include_sources] = true }
        parser.on("--restore-johann-history", "recover three verified Johann source originals from pub4 Git history into private sources/archive/") { options[:restore_johann_history] = true }
        parser.on("--apply", "copy local private files (default is dry-run)") { options[:apply] = true }
        parser.on("-h", "--help", "show this help") { puts parser; return { "status" => "help" } }
      end.parse!(argv)

      raise Error, "unexpected arguments: #{argv.join(" ")}" unless argv.empty?
      raise Error, "invalid subject name" if options[:subject] && !options[:subject].match?(SUBJECT_NAME)
      raise Error, "source checkout does not exist: #{options[:source]}" unless File.directory?(options[:source])
      raise Error, "source checkout must contain a .git directory or file" unless File.exist?(File.join(options[:source], ".git"))

      subjects = options[:subject] ? [options[:subject]] : %w[johann merethe ragnhild]
      reports = subjects.map { |subject| migrate_subject(subject, options) }
      {
        "status" => reports.any? { |row| row["status"] == "blocked" } ? "blocked" : "complete",
        "mode" => options[:apply] ? "apply" : "dry_run",
        "source_checkout" => options[:source],
        "include_sources" => options[:include_sources],
        "restore_johann_history" => options[:restore_johann_history],
        "subjects" => reports
      }
    end

    def migrate_subject(subject, options)
      destination = File.join(DESTINATION_ROOT, subject)
      candidates = SOURCE_ROOTS.map { |root| File.join(options[:source], root, subject) }
      candidates.select! { |path| File.directory?(path) && !File.symlink?(path) }
      history_entries = if subject == "johann" && options[:restore_johann_history]
                          recoverable_johann_history(options[:source])
                        else
                          []
                        end
      if candidates.empty? && history_entries.empty?
        return { "subject" => subject, "status" => "no_local_source_directory", "copied" => [] }
      end

      begin
        validate_destination_consent!(destination, subject)
      rescue Error => error
        return {
          "subject" => subject,
          "status" => "blocked",
          "reason" => error.message,
          "legacy_directories" => candidates
        }
      end

      entries = candidates.flat_map { |root| planned_entries(root, include_sources: options[:include_sources]) }
      entries.concat(history_entries)
      entries = entries.uniq { |entry| entry[:relative] }
      conflicts = entries.select do |entry|
        target = File.join(destination, entry[:relative])
        File.exist?(target) || File.symlink?(target)
      end
      return {
        "subject" => subject,
        "status" => "blocked",
        "reason" => "destination contains existing paths; refusing to overwrite",
        "conflicts" => conflicts.map { |entry| entry[:relative] },
        "planned" => entries.map { |entry| { "path" => entry[:relative], "bytes" => entry[:bytes] } }
      } unless conflicts.empty?

      if options[:apply]
        ensure_private_directory!(destination)
        entries.each do |entry|
          target = File.join(destination, entry[:relative])
          if entry[:history_bytes]
            copy_bytes_private!(entry[:history_bytes], target)
          else
            copy_private!(entry[:source], target)
          end
        end
      end

      {
        "subject" => subject,
        "status" => entries.empty? ? "no_eligible_files" : (options[:apply] ? "copied" : "ready"),
        "legacy_directories" => candidates,
        "copied" => entries.map { |entry| { "path" => entry[:relative], "bytes" => entry[:bytes] } }
      }
    end

    JOHANN_HISTORY_COMMIT = "4c0211c821954003998593d147629e8716c09ded".freeze
    JOHANN_HISTORY_FILES = {
      "20240627_000251.jpg" => "08cf030b763a919a71bd4dc19aa1da48313faa89",
      "20240705_161331.jpg" => "1db28036f6397d1a2f30da8d38385e1ab85e976b",
      "20260725_015451.jpg" => "cac622e9a061181a99738074909f4ef639ee35d2"
    }.freeze

    # These three Johann originals were removed from the current pub4 tree,
    # but remain in the recorded restoration commit. Recover them only when
    # explicitly requested, and verify the Git blob SHA before copying.
    def recoverable_johann_history(source_checkout)
      JOHANN_HISTORY_FILES.map do |filename, expected_sha|
        source_path = "STUDIO/lora/johann/sources/#{filename}"
        revision = "#{JOHANN_HISTORY_COMMIT}:#{source_path}"
        bytes, error, status = Open3.capture3("git", "-C", source_checkout, "show", revision, binmode: true)
        raise Error, "could not recover #{source_path} from local pub4 history: #{error.strip}" unless status.success?

        actual_sha = Digest::SHA1.hexdigest("blob #{bytes.bytesize}\\0".b + bytes)
        raise Error, "historical image hash mismatch for #{filename}" unless actual_sha == expected_sha

        { relative: File.join("sources", "archive", filename), bytes: bytes.bytesize, history_bytes: bytes }
      end
    end

    # Only copy the runtime inputs needed by the current Replicate route.
    # Historical datasets, retouched portraits, training worktrees and old
    # safetensors are intentionally not imported by this migration.
    def planned_entries(root, include_sources:)
      entries = []
      env = File.join(root, "subject.env")
      env = File.join(root, "ai_toolkit", "subject.env") unless File.file?(env)
      entries << entry(env, "subject.env") if File.file?(env) && !File.symlink?(env)

      Dir.glob(File.join(root, "weights", "*", "replicate_training.json")).sort.each do |path|
        next unless File.file?(path) && !File.symlink?(path)
        slug = File.basename(File.dirname(path))
        entries << entry(path, File.join("weights", slug, "replicate_training.json"))
      end

      if include_sources
        source_dir = File.join(root, "sources")
        walk_private_sources(source_dir).each do |path|
          relative = Pathname.new(path).relative_path_from(Pathname.new(source_dir)).to_s
          entries << entry(path, File.join("sources", relative))
        end
      end
      entries
    end

    def walk_private_sources(directory)
      return [] unless File.directory?(directory) && !File.symlink?(directory)

      files = []
      Dir.glob(File.join(directory, "**", "*"), File::FNM_DOTMATCH).sort.each do |path|
        next if %w[. ..].include?(File.basename(path))
        stat = File.lstat(path)
        raise Error, "source tree contains a symlink: #{path}" if stat.symlink?
        if stat.directory?
          next
        elsif stat.file?
          raise Error, "source file is too large to import: #{path}" if stat.size > 50 * 1024 * 1024
          files << path
        else
          raise Error, "unsupported source entry: #{path}"
        end
      end
      files
    end

    def entry(source, relative)
      stat = File.lstat(source)
      raise Error, "legacy input is not a regular file: #{source}" unless stat.file? && !stat.symlink?
      raise Error, "legacy input is not owned by the current user: #{source}" unless stat.uid == Process.uid
      { source: source, relative: relative, bytes: stat.size }
    end

    def validate_destination_consent!(destination, subject)
      path = File.join(destination, "consent.yml")
      stat = File.lstat(path)
      raise Error, "missing consent.yml; create it from STUDIO/photograph/consent.example.yml locally" unless stat.file? && !stat.symlink?
      raise Error, "consent.yml must be owned by the current user" unless stat.uid == Process.uid
      raise Error, "consent.yml must be private (0600)" unless (stat.mode & 0o077).zero?
      raise Error, "consent.yml is too large" if stat.size > 16_384
      record = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
      raise Error, "consent subject mismatch" unless record.is_a?(Hash) && record["schema"] == 1 && record["subject"] == subject
      person = record["subject_consent"]
      rights = record["source_rights"]
      raise Error, "likeness/provider-processing consent is incomplete" unless person.is_a?(Hash) && person["likeness_generation"] == true && person["provider_processing"] == true
      unless rights.is_a?(Hash) && rights["generation_use"] == true &&
             rights["provider_processing"] == true && rights["evidence"].to_s.strip.length >= 8
        raise Error, "source-rights/provider-processing evidence is incomplete"
      end
      true
    rescue Errno::ENOENT
      raise Error, "missing private consent.yml for #{subject}; create it from STUDIO/photograph/consent.example.yml locally"
    rescue Psych::Exception => error
      raise Error, "invalid consent YAML: #{error.message}"
    end

    def ensure_private_directory!(path)
      raise Error, "destination path is a symlink: #{path}" if File.symlink?(path)
      FileUtils.mkdir_p(path, mode: 0o700)
      File.chmod(0o700, path)
    end

    def copy_bytes_private!(bytes, destination)
      raise Error, "destination already exists: #{destination}" if File.exist?(destination) || File.symlink?(destination)
      ensure_private_directory!(File.dirname(destination))
      File.open(destination, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
        output.write(bytes)
        output.flush
        output.fsync
      end
      File.chmod(0o600, destination)
    end

    def copy_private!(source, destination)
      raise Error, "destination already exists: #{destination}" if File.exist?(destination) || File.symlink?(destination)
      ensure_private_directory!(File.dirname(destination))
      File.open(source, "rb") do |input|
        File.open(destination, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
          IO.copy_stream(input, output)
          output.flush
          output.fsync
        end
      end
      File.chmod(0o600, destination)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    puts JSON.pretty_generate(Studio::LoraLocalMigration.run(ARGV))
  rescue Studio::LoraLocalMigration::Error, SystemCallError => error
    warn "BLOCKED: #{error.class}: #{error.message}"
    exit 2
  end
end
