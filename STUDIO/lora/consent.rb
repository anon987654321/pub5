# frozen_string_literal: true

require "date"
require "yaml"

module Studio
  module Lora
    # Read-only consent gate shared by validation, local dataset preparation
    # and likeness generation. It never creates, edits or infers a consent record.
    module Consent
      ROOT = File.expand_path(__dir__).freeze
      MAX_RECORD_BYTES = 65_536
      MAX_EVIDENCE_BYTES = 5 * 1024 * 1024
      SUBJECT_NAME = /\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\z/.freeze
      REQUIRED_COVERAGE = %w[generation_use provider_processing].freeze
      IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze

      class Error < StandardError; end

      module_function

      def required_source_sets(subject:, subject_directory:)
        case subject.to_s
        when "merethe"
          additional = File.join(subject_directory, "sources", "additional")
          has_additional = File.directory?(additional) && !File.symlink?(additional) &&
                           Dir.children(additional).any? do |name|
                             IMAGE_EXTENSIONS.include?(File.extname(name).downcase) &&
                               File.file?(File.join(additional, name)) &&
                               !File.symlink?(File.join(additional, name))
                           end
          has_additional ? %w[me2_archive additional_images] : %w[me2_archive]
        when "wenche"
          %w[me2_archive website_photographs]
        else
          []
        end
      rescue SystemCallError
        []
      end

      def validate(subject:, subject_directory:, required_sources: nil)
        subject = subject.to_s
        directory = File.expand_path(subject_directory.to_s)
        required = required_sources || required_source_sets(
          subject:, subject_directory: directory
        )
        errors = []

        unless SUBJECT_NAME.match?(subject)
          errors << "subject must be a simple directory name"
          return result(subject, directory, errors)
        end

        unless File.directory?(directory) && !File.symlink?(directory)
          errors << "private subject directory is missing or is a symlink"
          return result(subject, directory, errors)
        end
        unless private_mode?(directory, directory: true)
          errors << "subject directory must not be accessible by group or other users (mode 0700)"
        end

        path = File.join(directory, "consent.yml")
        unless File.file?(path) && !File.symlink?(path)
          errors << "private consent.yml is missing"
          return result(subject, directory, errors)
        end
        unless private_mode?(path)
          errors << "consent.yml must be owner-only (mode 0600)"
        end
        if File.size(path) > MAX_RECORD_BYTES
          errors << "consent.yml exceeds #{MAX_RECORD_BYTES} bytes"
          return result(subject, directory, errors)
        end

        document = YAML.safe_load(
          File.read(path, encoding: "UTF-8"),
          permitted_classes: [], permitted_symbols: [], aliases: false
        )
        unless document.is_a?(Hash)
          errors << "consent.yml root must be a mapping"
          return result(subject, directory, errors)
        end

        errors << "consent schema must be 1" unless document["schema"] == 1
        errors << "consent subject must match #{subject.inspect}" unless document["subject"] == subject

        subject_consent = document["subject_consent"]
        unless subject_consent.is_a?(Hash) &&
               subject_consent["likeness_generation"] == true &&
               subject_consent["provider_processing"] == true
          errors << "subject_consent must explicitly approve likeness_generation and provider_processing"
        end

        rights = document["source_rights"]
        unless rights.is_a?(Hash) &&
               rights["generation_use"] == true &&
               rights["provider_processing"] == true
          errors << "source_rights must explicitly approve generation_use and provider_processing"
        end

        evidence = rights.is_a?(Hash) ? rights["evidence"] : nil
        unless evidence.is_a?(Hash) && !evidence.empty?
          errors << "source_rights.evidence must name at least one documented source set"
          evidence = {}
        end

        Array(required).each do |source|
          errors << "source-rights evidence is missing for #{source}" unless evidence.key?(source.to_s)
        end

        evidence.each do |source, entry|
          errors.concat(validate_evidence(
            source.to_s, entry, directory: directory
          ))
        end

        result(subject, directory, errors)
      rescue Psych::Exception, SystemCallError, IOError, EncodingError => error
        result(subject, directory, ["cannot read consent record: #{error.class}: #{error.message}"])
      end

      def require!(subject:, subject_directory:, required_sources: nil)
        report = validate(subject:, subject_directory:, required_sources:)
        return report if report.fetch("valid")

        raise Error, "#{subject}: likeness generation and provider processing blocked: #{report.fetch("errors").join("; ")}"
      end

      def validate_evidence(source, entry, directory:)
        errors = []
        unless source.match?(SUBJECT_NAME)
          return ["source-rights evidence contains an invalid source-set name"]
        end
        unless entry.is_a?(Hash)
          return ["#{source}: evidence entry must be a mapping"]
        end

        granted_by = entry["granted_by"].to_s.strip
        errors << "#{source}: granted_by is missing" if granted_by.empty?

        begin
          Date.iso8601(entry["granted_on"].to_s)
        rescue Date::Error
          errors << "#{source}: granted_on must be an ISO date (YYYY-MM-DD)"
        end

        covers = entry["covers"]
        covers = covers.split(",").map(&:strip) if covers.is_a?(String)
        covers = Array(covers).map(&:to_s)
        missing = REQUIRED_COVERAGE - covers
        errors << "#{source}: covers must include #{missing.join(" and ")}" unless missing.empty?

        stored_at = entry["stored_at"].to_s
        evidence_path = private_evidence_file(stored_at, directory:)
        errors << "#{source}: stored_at must name an existing private, non-symlink evidence file inside the subject directory" unless evidence_path
        errors
      end
      private_class_method :validate_evidence

      def private_evidence_file(relative, directory:)
        return nil if relative.empty? || relative.include?("\\") || relative.start_with?(File::SEPARATOR)

        parts = relative.split(File::SEPARATOR)
        return nil if parts.any? { |part| part.empty? || part == "." || part == ".." }

        cursor = directory
        parts.each do |part|
          cursor = File.join(cursor, part)
          return nil if File.symlink?(cursor)
          return nil unless File.exist?(cursor)
          return nil if File.directory?(cursor) && !private_mode?(cursor, directory: true)
        end

        return nil unless File.file?(cursor)
        return nil unless File.size(cursor).between?(1, MAX_EVIDENCE_BYTES)
        return nil unless private_mode?(cursor)

        root = File.realpath(directory)
        real = File.realpath(cursor)
        return nil unless real.start_with?("#{root}#{File::SEPARATOR}")

        cursor
      rescue SystemCallError
        nil
      end
      private_class_method :private_evidence_file

      def private_mode?(path, directory: false)
        stat = File.stat(path)
        return false if (stat.mode & 0o077).positive?

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
