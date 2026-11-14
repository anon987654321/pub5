# frozen_string_literal: true

require "date"
require "yaml"

module Studio
  module Lora
    # Read-only, action-scoped permission gate for identity media. The gate
    # never creates consent, interprets a public URL as permission, or repairs
    # an incomplete record.
    module Consent
      MAX_RECORD_BYTES = 65_536
      MAX_EVIDENCE_BYTES = 5 * 1024 * 1024
      SUBJECT_NAME = /\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\z/.freeze
      IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze

      SUBJECT_PERMISSIONS = {
        generation: %w[likeness_generation provider_processing].freeze,
        training: %w[likeness_generation provider_processing model_training model_retention].freeze,
        publication: %w[model_publication].freeze,
        distribution: %w[model_distribution].freeze
      }.freeze

      SOURCE_PERMISSIONS = {
        generation: %w[generation_use provider_processing].freeze,
        training: %w[generation_use provider_processing training_use].freeze,
        publication: %w[model_publication].freeze,
        distribution: %w[model_distribution].freeze
      }.freeze

      class Error < StandardError; end

      module_function

      def required_source_sets(subject:, subject_directory:)
        directory = File.expand_path(subject_directory.to_s)
        if subject.to_s == "merethe"
          sources = File.join(directory, "sources")
          additional = File.join(sources, "additional")
          sets = []
          sets << "me2_archive" if local_images?(sources, direct_only: true)
          sets << "additional_images" if local_images?(additional)
          return sets
        end

        sets = []
        sets << "reference_photographs" if local_images?(File.join(directory, "references"))
        sets << "subject_sources" if local_images?(File.join(directory, "sources"))
        sets << "training_dataset" if local_images?(File.join(directory, "dataset"))
        sets
      end

      def validate(subject:, subject_directory:, required_sources: nil, action: :generation)
        subject = subject.to_s
        directory = File.expand_path(subject_directory.to_s)
        action = action.to_sym
        subject_scopes = SUBJECT_PERMISSIONS[action]
        source_scopes = SOURCE_PERMISSIONS[action]
        errors = []

        unless subject_scopes && source_scopes
          return result(subject, directory, ["unsupported consent action: #{action.inspect}"])
        end
        unless SUBJECT_NAME.match?(subject)
          return result(subject, directory, ["subject must be a simple directory name"])
        end
        unless File.directory?(directory) && !File.symlink?(directory)
          return result(subject, directory, ["subject directory is missing or is a symlink"])
        end

        consent_path = File.join(directory, "consent.yml")
        unless File.file?(consent_path) && !File.symlink?(consent_path)
          return result(subject, directory, ["private consent.yml is missing"])
        end
        errors << "consent.yml must be owner-only (mode 0600)" unless private_mode?(consent_path)
        return result(subject, directory, errors) if File.size(consent_path) > MAX_RECORD_BYTES

        document = YAML.safe_load(
          File.read(consent_path, encoding: "UTF-8"),
          permitted_classes: [], permitted_symbols: [], aliases: false
        )
        unless document.is_a?(Hash)
          return result(subject, directory, ["consent.yml root must be a mapping"])
        end

        errors << "consent schema must be 1" unless document["schema"] == 1
        errors << "consent subject must match #{subject.inspect}" unless document["subject"] == subject

        subject_consent = document["subject_consent"]
        unless subject_consent.is_a?(Hash)
          errors << "subject_consent must be a mapping"
          subject_consent = {}
        end
        missing_subject_scopes = subject_scopes.reject { |scope| subject_consent[scope] == true }
        errors << "subject_consent must explicitly approve #{missing_subject_scopes.join(', ')} for #{action}" unless missing_subject_scopes.empty?
        errors.concat(validate_evidence(
          "subject_consent", subject_consent["evidence"], directory:,
          required_coverage: subject_scopes
        ))

        rights = document["source_rights"]
        unless rights.is_a?(Hash)
          errors << "source_rights must be a mapping"
          rights = {}
        end
        missing_source_scopes = source_scopes.reject { |scope| rights[scope] == true }
        errors << "source_rights must explicitly approve #{missing_source_scopes.join(', ')} for #{action}" unless missing_source_scopes.empty?

        evidence = rights["evidence"]
        unless evidence.nil? || evidence.is_a?(Hash)
          errors << "source_rights.evidence must be a mapping"
          evidence = {}
        end
        evidence ||= {}

        required = required_sources || required_source_sets(subject:, subject_directory: directory)
        Array(required).each do |source|
          errors << "source-rights evidence is missing for #{source}" unless evidence.key?(source.to_s)
        end
        evidence.each do |source, entry|
          errors.concat(validate_evidence(source.to_s, entry, directory:, required_coverage: source_scopes))
        end

        result(subject, directory, errors)
      rescue Error, Psych::Exception, SystemCallError, IOError, EncodingError, ArgumentError, TypeError => error
        result(subject, directory, ["cannot validate consent: #{error.class}: #{error.message}"])
      end

      def require!(subject:, subject_directory:, required_sources: nil, action: :generation)
        report = validate(subject:, subject_directory:, required_sources:, action:)
        return report if report.fetch("valid")

        raise Error, "#{subject}: #{action} blocked: #{report.fetch('errors').join('; ')}"
      end

      def local_images?(directory, direct_only: false)
        raise Error, "refusing symlink source directory: #{directory}" if File.symlink?(directory)
        return false unless File.directory?(directory)

        Dir.children(directory).any? do |name|
          path = File.join(directory, name)
          next false unless IMAGE_EXTENSIONS.include?(File.extname(name).downcase)
          raise Error, "refusing symlink source image: #{path}" if File.symlink?(path)

          File.file?(path)
        end
      rescue SystemCallError => error
        raise Error, "cannot inventory source directory #{directory}: #{error.class}: #{error.message}"
      end
      private_class_method :local_images?

      def validate_evidence(source, entry, directory:, required_coverage:)
        unless SUBJECT_NAME.match?(source)
          return ["source-rights evidence contains an invalid source-set name"]
        end
        return ["#{source}: evidence entry must be a mapping"] unless entry.is_a?(Hash)

        errors = []
        granted_by = entry["granted_by"]
        errors << "#{source}: granted_by must name the permission-granting person or organisation" unless
          granted_by.is_a?(String) && !granted_by.strip.empty?

        granted_on = entry["granted_on"]
        begin
          parsed_date = Date.iso8601(granted_on) if granted_on.is_a?(String)
          errors << "#{source}: granted_on must be a quoted ISO date (YYYY-MM-DD)" unless
            parsed_date && parsed_date.strftime("%Y-%m-%d") == granted_on
        rescue Date::Error
          errors << "#{source}: granted_on must be a quoted ISO date (YYYY-MM-DD)"
        end

        covers = entry["covers"]
        covers = covers.split(",").map(&:strip) if covers.is_a?(String)
        covers = Array(covers).map(&:to_s)
        missing = required_coverage - covers
        errors << "#{source}: covers must include #{missing.join(' and ')}" unless missing.empty?

        stored_at = entry["stored_at"]
        evidence_path = private_evidence_file(stored_at, directory:) if stored_at.is_a?(String)
        errors << "#{source}: stored_at must name a separate, existing private, non-symlink evidence file inside evidence/" unless evidence_path
        errors
      end
      private_class_method :validate_evidence

      def private_evidence_file(relative, directory:)
        return nil unless relative.start_with?("evidence/")
        return nil if relative.include?("\\") || relative.start_with?("/")

        parts = relative.split("/")
        return nil if parts.any? { |part| part.empty? || part == "." || part == ".." }

        cursor = directory
        parts.each do |part|
          cursor = File.join(cursor, part)
          stat = File.lstat(cursor)
          return nil if stat.symlink?
          return nil if stat.directory? && !private_mode?(cursor, directory: true)
        end

        stat = File.lstat(cursor)
        return nil unless stat.file? && stat.size.between?(1, MAX_EVIDENCE_BYTES)
        return nil unless stat.nlink == 1 && private_mode?(cursor)

        root = File.realpath(directory)
        real = File.realpath(cursor)
        return nil unless real.start_with?("#{root}#{File::SEPARATOR}")

        cursor
      rescue SystemCallError
        nil
      end
      private_class_method :private_evidence_file

      def private_mode?(path, directory: false)
        stat = File.lstat(path)
        return false if stat.symlink? || (stat.mode & 0o077).positive?

        required_bit = directory ? 0o100 : 0o400
        (stat.mode & required_bit).positive?
      rescue SystemCallError
        false
      end
      private_class_method :private_mode?

      def result(subject, directory, errors)
        {
          "subject" => subject,
          "subject_directory" => directory,
          "consent_path" => File.join(directory, "consent.yml"),
          "valid" => errors.empty?,
          "errors" => errors
        }
      end
      private_class_method :result
    end
  end
end
