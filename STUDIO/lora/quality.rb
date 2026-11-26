#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "optparse"
require "time"
require "vips"
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

      # A deliberate sitting declares its shot design in the prompt itself:
      # framing (the crop), lens or distance (the projection), light (the one
      # thing a grade can only deepen), moment (an observed, not performed,
      # expression), eye-line (where the subject looks) and flaw (the
      # imperfection a real camera leaves behind). A scene missing an axis asks
      # the model to guess it, and the guess is always the average; a scene with
      # no flaw reads as a composite, because nothing in the world is that
      # clean. The matchers are deliberately lexical: they gate the presence of
      # the decision, not its poetry.
      SCENE_AXES = {
        "framing" => /crop|fram|head[ -]and[ -]shoulders|waist[ -]up|mid[ -]torso|chest[ -]up/i,
        "lens_or_distance" => /\b\d+\s?mm\b|\bdistance\b|metre|meter|arm's length/i,
        "light" => /sun|light|lamp|haze|neon|tungsten|overcast|golden|dusk|dawn|blue hour|daylight|catchlight|candle|flame|softbox|shade|backlit|window/i,
        "moment" => /laugh|grin|smile|expression|amused|unguarded|tired|breath|mid[ -]word|concentration|thoughtful|mid[ -]thought|calm|composed|contemplat|reflective|candid|composure|performed/i,
        "eye_line" => /eye|gaze|to[ -](the[ -])?lens|on the lens|past the lens/i,
        "flaw" => /blown|clipped|smudge|spray|flare|halation|dust|motion\s+blur|
                   rain\s+on\s+the\s+(lens|window)|strand\s+of\s+hair|hair\s+across|
                   eye\s+in\s+shadow|a\s+degree\s+off|cutting\s+the\s+(top|bottom)\s+corner|
                   cut\s+by\s+the\s+frame|blurred\s+across\s+the\s+foreground|
                   soft\s+in\s+the\s+foreground|softbox\s+edge/ix,
      }.freeze

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

      # Every sitting in the shared and per-subject scene sets must declare all
      # six shot-design axes. Read-only: this audits the prompt bodies, never
      # a provider.
      def audit_scene_design(scenes: nil, subject_scenes: nil)
        scenes ||= Selfie::SCENES
        subject_scenes ||= Selfie::SUBJECT_SCENES
        rows = []
        scenes.each_with_index do |body, index|
          rows << scene_row("scene #{index + 1}", body)
        end
        subject_scenes.each do |subject, list|
          list.each_with_index do |body, index|
            rows << scene_row("#{subject} scene #{index + 1}", body)
          end
        end
        {
          "state" => rows.all? { |row| row["state"] == "PASS" } ? "PASS" : "FAIL",
          "axes" => SCENE_AXES.keys,
          "scene_count" => rows.length,
          "scenes" => rows,
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

      # 9x8 greyscale thumbnails reduced to a 64-bit difference hash. Two
      # photographs of the same subject in different clothes and light still
      # differ in most bits; two crops of one frame barely differ at all.
      def dhash(path)
        image = Vips::Image.new_from_file(path, access: :random).colourspace("b-w")
        image = image.resize(9.0 / image.width, vscale: 8.0 / image.height)
        pixels = image.to_a.flatten
        hash = 0
        8.times do |row|
          8.times do |column|
            hash = (hash << 1) | (pixels[row * 9 + column] > pixels[row * 9 + column + 1] ? 1 : 0)
          end
        end
        hash
      end

      def hamming(a, b) = (a ^ b).to_s(2).count("1")

      # Pure: pair every hash, keep the pairs too close to be different
      # photographs. Threshold is bits out of 64.
      def near_duplicate_pairs(hashes, threshold: 5)
        hashes.combination(2).filter_map do |(name_a, hash_a), (name_b, hash_b)|
          distance = hamming(hash_a, hash_b)
          { "pair" => [name_a, name_b], "distance" => distance } if distance <= threshold
        end
      end

      # A training set should be many distinct photographs of one person, not a
      # few frames in disguise: near-duplicates teach the model a smaller set
      # than the image count claims. WARN, not BLOCK - a deliberate burst can
      # be legitimate, but it must be a decision, not an accident.
      def dataset_diversity(subject:, root: ROOT)
        name = subject.to_s
        dataset = File.join(File.expand_path(root), name, STANDARD.fetch("dataset").fetch("path"))
        return { "state" => "UNKNOWN", "detail" => "no dataset" } unless File.directory?(dataset) && !File.symlink?(dataset)

        images = Dir.children(dataset).sort.select { |entry| IMAGE_EXTENSIONS.include?(File.extname(entry).downcase) }
        return { "state" => "UNKNOWN", "detail" => "no images" } if images.empty?

        hashes = images.map { |entry| [entry, dhash(File.join(dataset, entry))] }
        duplicates = near_duplicate_pairs(hashes)
        state = duplicates.empty? ? "PASS" : "WARN"
        {
          "state" => state,
          "image_count" => images.length,
          "near_duplicate_pairs" => duplicates,
          "detail" => duplicates.empty? ? "all #{images.length} images are perceptually distinct" :
            "#{duplicates.length} near-duplicate pair(s) - the dataset trains as smaller than it looks",
        }
      rescue SystemCallError, IOError => error
        { "state" => "UNKNOWN", "detail" => error.message }
      end

      # The likeness approval state for a subject, derived from evidence, not
      # from the presence of an env value alone. Pure decision so the states
      # are testable: NEVER_REVIEWED (no approval, no receipt), CURRENT
      # (approved version matches a recent receipt on the active profile),
      # STALE_AGE (receipt older than approval_max_age_days),
      # STALE_PROFILE (approved against a different inference profile than the
      # one renders now use), UNREVIEWED_VERSION (a pinned version no review
      # receipt covers).
      def approval_state(approved_version:, receipt:, current_profile:, max_age_days:, today:)
        return "NEVER_REVIEWED" if approved_version.to_s.empty? && receipt.nil?
        return "UNREVIEWED_VERSION" if receipt.nil? || receipt["model_version"].to_s != approved_version.to_s
        return "STALE_PROFILE" if receipt["inference_profile"].to_s != current_profile.to_s

        age = (today - receipt["reviewed_at"]).to_i
        age > max_age_days ? "STALE_AGE" : "CURRENT"
      end

      def approval_status(subject:, root: ROOT, today: Date.today)
        name = subject.to_s
        subject_directory = File.join(File.expand_path(root), name)
        env_path = File.join(subject_directory, "subject.env")
        approved = if File.file?(env_path) && !File.symlink?(env_path)
                     File.readlines(env_path, chomp: true).filter_map do |line|
                       match = /\ALIKELINESS_REVIEWED_VERSION=(.*)\z/.match(line.strip)
                       match && match[1].strip.gsub(/\A["']|["']\z/, "")
                     end.last
                   end
        receipt = latest_review_receipt(subject_directory)
        state = approval_state(
          approved_version: approved,
          receipt: receipt,
          current_profile: default_profile,
          max_age_days: STANDARD.fetch("review").fetch("approval_max_age_days"),
          today: today
        )
        {
          "state" => state,
          "approved_version" => approved,
          "receipt_profile" => receipt && receipt["inference_profile"],
          "receipt_date" => receipt && receipt["reviewed_at"]&.iso8601,
        }
      rescue SystemCallError, IOError
        { "state" => "UNKNOWN" }
      end

      # The newest likeness-review receipt, from either the candidate or the
      # final review directory; the directory name is the UTC stamp.
      def latest_review_receipt(subject_directory)
        cache = File.join(subject_directory, ".cache")
        candidates = %w[likeness-review reviews].flat_map do |kind|
          root = File.join(cache, kind)
          next [] unless File.directory?(root) && !File.symlink?(root)

          Dir.children(root).filter_map do |stamp|
            receipt = File.join(root, stamp, "review.json")
            next unless File.file?(receipt) && !File.symlink?(receipt)

            digits = stamp[/\A\d{14}/].to_s
            reviewed_at = begin
              Time.strptime(digits, "%Y%m%d%H%M%S")
            rescue ArgumentError
              nil
            end
            next unless reviewed_at

            data = JSON.parse(File.read(receipt, encoding: "UTF-8"))
            {
              "model_version" => data["model_version"].to_s,
              "inference_profile" => data["inference_profile"].to_s,
              "reviewed_at" => reviewed_at.to_date,
              "stamp" => stamp,
              "receipt_path" => receipt,
            }
          rescue JSON::ParserError, SystemCallError
            nil
          end
        end
        candidates.max_by { |entry| entry.fetch("stamp") }
      end

      # Pure verdict over per-image hash comparisons: INTACT when every
      # reviewed image still holds the bytes the verdict was made on, DRIFT
      # when any changed or vanished, UNKNOWN when there is nothing to check
      # (no receipt yet, or a receipt from before hashes were recorded).
      def provenance_verdict(rows)
        return "UNKNOWN" if rows.nil?

        return "PROVENANCE_DRIFT" if rows.any? { |row| row["status"] != "MATCH" }

        "PROVENANCE_INTACT"
      end

      # Verify the newest review receipt against the files it judged. A render
      # edited or replaced after review silently voids the verdict; this makes
      # the void visible.
      def provenance_check(receipt)
        return { "state" => "UNKNOWN", "detail" => "no review receipt" } unless receipt

        data = JSON.parse(File.read(receipt.fetch("receipt_path"), encoding: "UTF-8"))
        entries = Array(data["images"])
        return { "state" => "UNKNOWN", "detail" => "receipt predates provenance hashes" } if
          entries.empty? || entries.any? { |entry| entry["sha256"].to_s.empty? }

        receipt_dir = File.dirname(receipt.fetch("receipt_path"))
        rows = entries.map do |entry|
          path = File.expand_path(entry.fetch("relative_path"), receipt_dir)
          status = if !File.file?(path) || File.symlink?(path)
                     "MISSING"
                   elsif Digest::SHA256.file(path).hexdigest == entry.fetch("sha256")
                     "MATCH"
                   else
                     "CHANGED"
                   end
          { "file" => entry.fetch("file"), "role" => entry["role"], "status" => status }
        end
        {
          "state" => provenance_verdict(rows),
          "receipt" => File.basename(receipt.fetch("receipt_path")),
          "images" => rows,
        }
      rescue JSON::ParserError, SystemCallError, IOError => error
        { "state" => "UNKNOWN", "detail" => error.message }
      end

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
        diversity = dataset_diversity(subject: name)
        approval = approval_status(subject: name)
        provenance = provenance_check(latest_review_receipt(File.join(ROOT, name)))
        ready = training["training_ready"] == true &&
                holdout_count.is_a?(Integer) && review_consent["valid"] == true
        {
          "subject" => name,
          "state" => ready ? "READY_FOR_CANDIDATE_REVIEW" : "BLOCKED",
          "training_ready" => training["training_ready"] == true,
          "training_blockers" => Array(training["blockers"]).map { |item| item["detail"] || item["id"] },
          "holdout_count" => holdout_count.is_a?(Integer) ? holdout_count : nil,
          "holdout_state" => holdout_count.is_a?(Integer) ? "PASS" : "BLOCKED",
          "dataset_diversity" => diversity,
          "approval" => approval,
          "provenance" => provenance,
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
                  Validator.subject_names(root: ROOT)
                end
        subjects = names.map do |name|
          subject_report(name)
        rescue Error => error
          { "subject" => name, "state" => "BLOCKED", "detail" => error.message, "provider_calls" => 0 }
        end
        scene_design = audit_scene_design
        state = configuration["state"] == "PASS" && scene_design["state"] == "PASS" && !subjects.empty? &&
                subjects.all? { |entry| entry["state"] == "READY_FOR_CANDIDATE_REVIEW" } ? "PASS" : "BLOCKED"
        {
          "schema" => "studio.lora.quality.v1",
          "state" => state,
          "read_only" => true,
          "provider_calls" => 0,
          "configuration" => configuration,
          "scene_design" => scene_design,
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

      def scene_row(id, body)
        missing = SCENE_AXES.reject { |_axis, matcher| body.match?(matcher) }.keys
        {
          "id" => id,
          "state" => missing.empty? ? "PASS" : "FAIL",
          "missing" => missing,
        }
      end
      private_class_method :scene_row

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
          design = result.fetch("scene_design")
          puts "Scene shot design: #{design.fetch("state")} (#{design.fetch("scene_count")} sittings, axes: #{design.fetch("axes").join(", ")})"
          design.fetch("scenes").select { |row| row["state"] == "FAIL" }.each do |row|
            puts "  #{row.fetch("id")}: missing #{row.fetch("missing").join(", ")}"
          end
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
