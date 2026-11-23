#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require "yaml"
require_relative "consent"
require_relative "validate"
require_relative "lora"

module Studio
  module Lora
    # Read-only photographic quality gate. It audits configuration, private
    # evaluation material and action-scoped consent; it never calls a provider.
    module Quality
      ROOT = File.expand_path(__dir__).freeze
      STANDARDS_PATH = File.join(ROOT, "training_standards.yml").freeze
      STANDARD = YAML.safe_load_file(STANDARDS_PATH, permitted_classes: [], permitted_symbols: [], aliases: false).freeze
      GUIDES = Studio::Lora::Guides.load.freeze
      IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze
      SUBJECT_NAME = /\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\z/.freeze

      class Error < StandardError; end

      module_function

      def default_profile
        STANDARD.fetch("inference").fetch("profile")
      end

      def profiles
        STANDARD.fetch("inference").fetch("profiles")
      end

      def evaluation_directory_name
        STANDARD.fetch("review").fetch("evaluation_directory")
      end

      def audit_configuration
        inference = STANDARD.fetch("inference")
        guide = GUIDES.fetch("prompting").fetch("flux_dev_lora")
        guidance_range = guide.fetch("guidance_range").map(&:to_f)
        steps_range = guide.fetch("steps").map(&:to_i)
        guide_scale_range = guide.fetch("lora_scale_range").map(&:to_f)
        checks = []
        checks << check(
          "default_profile", profiles.key?(default_profile),
          "The active profile exists in the shared inference profile map"
        )
        checks << check(
          "lossless_lora_master", inference["output_format"] == "png" && inference["output_quality"].nil?,
          "LoRA masters are requested as PNG without a lossy quality setting"
        )
        checks << check(
          "deterministic_inference", inference["go_fast"] == false && inference["seed"].is_a?(Integer),
          "The default LoRA path pins a seed and disables the non-deterministic fast path"
        )
        profiles.each do |name, values|
          valid = values.is_a?(Hash) &&
                  values["guidance_scale"].is_a?(Numeric) &&
                  values["guidance_scale"].to_f.between?(*guidance_range) &&
                  values["num_inference_steps"].is_a?(Integer) &&
                  values["num_inference_steps"].between?(*steps_range) &&
                  values["lora_scale"].is_a?(Numeric) &&
                  values["lora_scale"].to_f.between?(*guide_scale_range)
          checks << check(
            "profile_#{name}", valid,
            "Guidance, steps and LoRA strength stay inside documented and provider operating ranges"
          )
        end
        {
          "state" => checks.all? { |item| item["state"] == "PASS" } ? "PASS" : "FAIL",
          "checks" => checks,
          "default_profile" => default_profile,
          "profiles" => profiles.map do |name, values|
            {
              "name" => name,
              "settings" => values,
              "status" => "UNBENCHMARKED",
              "candidate_command" => "ruby STUDIO/lora/review.rb --subject NAME --candidate --profile #{name}",
            }
          end,
          "comparison_method" => "Render the same three candidate scenes for each profile; compare all outputs against the same independent holdout set at full resolution. Record a human verdict; do not promote a profile from metrics alone.",
        }
      rescue KeyError, NoMethodError, TypeError => error
        {
          "state" => "FAIL",
          "checks" => [{ "id" => "configuration_schema", "state" => "FAIL", "detail" => error.message }],
          "profiles" => [],
        }
      end

      def evaluation_files(subject:, root: ROOT)
        name = subject.to_s
        raise Error, "subject must be a simple directory name" unless SUBJECT_NAME.match?(name)

        subject_directory = File.join(File.expand_path(root), name)
        secure_directory!(subject_directory, "subject directory")
        evaluation = File.join(subject_directory, evaluation_directory_name)
        secure_directory!(evaluation, "private evaluation directory")

        dataset = File.join(subject_directory, STANDARD.fetch("dataset").fetch("path"))
        secure_directory!(dataset, "private training dataset")

        training_files = private_images(dataset)
        holdout_files = private_images(evaluation)
        minimum = STANDARD.fetch("review").fetch("min_evaluation_images")
        maximum = STANDARD.fetch("review").fetch("max_evaluation_images")
        raise Error, "holdout set needs at least #{minimum} private photographs; found #{holdout_files.length}" if holdout_files.length < minimum
        raise Error, "holdout set exceeds the configured maximum of #{maximum} photographs" if holdout_files.length > maximum

        training_hashes = training_files.to_h { |path| [Digest::SHA256.file(path).hexdigest, path] }
        holdout_hashes = {}
        holdout_files.each do |path|
          digest = Digest::SHA256.file(path).hexdigest
          raise Error, "duplicate image inside evaluation set: #{File.basename(path)}" if holdout_hashes.key?(digest)
          raise Error, "evaluation image overlaps the training dataset: #{File.basename(path)}" if training_hashes.key?(digest)

          holdout_hashes[digest] = path
        end
        holdout_files
      rescue SystemCallError, IOError => error
        raise Error, "cannot inventory private holdout photographs: #{error.class}"
      end

      def private_images(directory)
        Dir.children(directory).sort.filter_map do |filename|
          next unless IMAGE_EXTENSIONS.include?(File.extname(filename).downcase)

          path = File.join(directory, filename)
          stat = File.lstat(path)
          unless stat.file? && !stat.symlink? && stat.uid == Process.uid &&
                 stat.nlink == 1 && (stat.mode & 0o077).zero? && stat.size.positive?
            raise Error, "image must be a non-empty, singly-linked owner-only file: #{filename}"
          end
          path
        end
      end
      private_class_method :private_images

      def secure_directory!(path, label)
        raise Error, "#{label} is missing or symlinked" unless File.directory?(path) && !File.symlink?(path)

        stat = File.lstat(path)
        unless stat.directory? && stat.uid == Process.uid && (stat.mode & 0o077).zero?
          raise Error, "#{label} must be current-user-owned and owner-only (0700)"
        end
        true
      end
      private_class_method :secure_directory!

      def subject_report(subject)
        name = subject.to_s
        raise Error, "subject must be a simple directory name" unless SUBJECT_NAME.match?(name)

        training = Validator.new.validate_subject(name)
        holdout_count = begin
          evaluation_files(subject: name).length
        rescue Error => error
          error.message
        end
        review_consent = Consent.validate(
          subject: name, subject_directory: File.join(ROOT, name),
          action: :likeness_review, required_sources: ["evaluation_photographs"]
        )
        ready = training["training_ready"] == true &&
                holdout_count.is_a?(Integer) && review_consent["valid"] == true
        {
          "subject" => name,
          "state" => ready ? "READY_FOR_CANDIDATE_REVIEW" : "BLOCKED",
          "training_ready" => training["training_ready"] == true,
          "training_blockers" => Array(training["blockers"]).map { |item| item["detail"] || item["id"] },
          "holdout_count" => holdout_count.is_a?(Integer) ? holdout_count : nil,
          "holdout_state" => holdout_count.is_a?(Integer) ? "PASS" : "BLOCKED",
          "holdout_detail" => holdout_count.is_a?(String) ? holdout_count : nil,
          "review_consent_valid" => review_consent["valid"] == true,
          "review_consent_errors" => Array(review_consent["errors"]),
          "provider_calls" => 0,
        }
      end

      def report(subject: nil)
        configuration = audit_configuration
        names = if subject && !subject.to_s.empty?
                  [subject.to_s]
                else
                  Dir.children(ROOT).select do |entry|
                    SUBJECT_NAME.match?(entry) && File.directory?(File.join(ROOT, entry)) && !File.symlink?(File.join(ROOT, entry))
                  end.sort
                end
        subjects = names.map do |name|
          subject_report(name)
        rescue Error => error
          { "subject" => name, "state" => "BLOCKED", "detail" => error.message, "provider_calls" => 0 }
        end
        state = configuration["state"] == "PASS" && !subjects.empty? &&
                subjects.all? { |entry| entry["state"] == "READY_FOR_CANDIDATE_REVIEW" } ? "PASS" : "BLOCKED"
        {
          "schema" => "studio.lora.quality.v1",
          "state" => state,
          "read_only" => true,
          "provider_calls" => 0,
          "configuration" => configuration,
          "comparison_status" => "UNBENCHMARKED",
          "subjects" => subjects,
          "film_review" => {
            "identity_continuity" => "HUMAN_REVIEW_REQUIRED",
            "temporal_artifacts" => "HUMAN_REVIEW_REQUIRED",
            "camera_motion" => "HUMAN_REVIEW_REQUIRED",
            "lighting_continuity" => "HUMAN_REVIEW_REQUIRED",
            "soundtrack_and_mix" => "HUMAN_REVIEW_REQUIRED",
          },
        }
      end

      def check(id, passed, detail)
        { "id" => id, "state" => passed ? "PASS" : "FAIL", "detail" => detail }
      end
      private_class_method :check

      def run_cli(argv)
        options = { subject: nil, json: false }
        OptionParser.new do |parser|
          parser.banner = "Usage: ruby STUDIO/lora/quality.rb [--subject NAME] [--json]"
          parser.on("--subject NAME", "Audit one subject's training, holdout and consent state") { |value| options[:subject] = value }
          parser.on("--json", "Print the full machine-readable quality report") { options[:json] = true }
          parser.on("-h", "--help", "Show this help") { puts parser; return 0 }
        end.parse!(argv)
        result = report(subject: options[:subject])
        if options[:json]
          puts JSON.pretty_generate(result)
        else
          puts "Photographic configuration: #{result.dig("configuration", "state")}"
          result.fetch("configuration").fetch("profiles", []).each do |profile|
            puts "  #{profile.fetch("name")}: UNBENCHMARKED — #{profile.fetch("settings").inspect}"
          end
          result.fetch("subjects").each do |entry|
            puts "#{entry.fetch("subject")}: #{entry.fetch("state")}"
            puts "  holdout: #{entry.fetch("holdout_detail")}" if entry["holdout_detail"]
            Array(entry["training_blockers"]).each { |message| puts "  training: #{message}" }
            Array(entry["review_consent_errors"]).each { |message| puts "  consent: #{message}" }
          end
          puts "No provider calls were made."
        end
        result.fetch("state") == "PASS" ? 0 : 1
      rescue Error, Psych::Exception, SystemCallError, IOError, ArgumentError => error
        warn "BLOCKED: #{error.class}: #{error.message}"
        2
      end
    end
  end
end

exit Studio::Lora::Quality.run_cli(ARGV) if $PROGRAM_NAME == __FILE__
