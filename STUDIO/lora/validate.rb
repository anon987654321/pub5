# frozen_string_literal: true

require "json"
require "yaml"
require_relative "consent"

module Studio
  module Lora
    # Read-only audit of subject descriptors and local training plans. This is
    # deliberately not a trainer: it never uploads data, creates a provider
    # model, starts training, or writes into a subject directory.
    class Validator
      ROOT = File.expand_path(__dir__).freeze
      STANDARDS_PATH = File.join(ROOT, "training_standards.yml").freeze
      TRAINING_STANDARD = YAML.safe_load_file(STANDARDS_PATH, permitted_classes: [], permitted_symbols: [], aliases: false).freeze
      SUBJECT_NAME = /\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\z/.freeze
      ENV_KEYS = %w[SUBJECT MODEL TRIGGER DESCRIPTOR REPLICATE_DESTINATION REPLICATE_MODEL LIKELINESS_REVIEWED_VERSION].freeze
      IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze
      MINIMUM_IMAGES = TRAINING_STANDARD.fetch("quality").fetch("min_images")
      MAXIMUM_IMAGES = TRAINING_STANDARD.fetch("quality").fetch("max_images")
      MAX_CAPTION_BYTES = 16_384
      MAX_CONFIG_BYTES = 1_048_576

      def initialize(root: ROOT)
        @root = File.expand_path(root)
      end

      def validate_all
        raise ArgumentError, "LoRA root is not a readable directory: #{@root}" unless File.directory?(@root) && !File.symlink?(@root)

        subjects = Dir.children(@root).sort.filter_map do |name|
          next unless SUBJECT_NAME.match?(name)

          path = File.join(@root, name)
          next unless File.directory?(path) && !File.symlink?(path)

          validate_subject(name)
        end

        {
          "schema" => "studio.lora.validation.v1",
          "read_only" => true,
          "provider_calls" => 0,
          "subject_count" => subjects.length,
          "subjects" => subjects,
        }
      end

      def validate_subject(name)
        subject = name.to_s
        raise ArgumentError, "subject must be a simple directory name" unless SUBJECT_NAME.match?(subject)

        directory = File.join(@root, subject)
        raise ArgumentError, "subject directory is missing or is a symlink: #{subject}" unless File.directory?(directory) && !File.symlink?(directory)

        report = {
          "subject" => subject,
          "state" => "PASS",
          "training_ready" => false,
          "training_readiness" => "BLOCKED",
          "descriptor" => nil,
          "model" => nil,
          "trigger" => nil,
          "checks" => [],
          "blockers" => [],
          "warnings" => [],
        }

        consent = Consent.validate(subject:, subject_directory: directory, action: :training)
        report["consent_valid"] = consent.fetch("valid")
        if consent.fetch("valid")
          pass_check(report, "subject_consent", "Private written consent and per-source rights cover training and retention")
        else
          block(report, "subject_consent", consent.fetch("errors").join("; "))
        end

        private_env_path = File.join(directory, "subject.env")
        if File.exist?(private_env_path) || File.symlink?(private_env_path)
          env_path = private_env_path
          unless File.file?(env_path) && !File.symlink?(env_path)
            fail_check(report, "subject_descriptor_path", "Private subject.env must be a regular, non-symlink file")
            return report
          end
        else
          example_path = File.join(directory, "subject.env.example")
          env_path = example_path if File.file?(example_path) && !File.symlink?(example_path)
        end
        unless env_path
          # A subject with no descriptor is not configured yet — the public
          # checkout ships none, by design: consent and subject.env are private,
          # owner-only files. FAIL is for an artifact that exists and violates
          # its schema; absence is a blocker, the same class as missing consent.
          block(report, "subject_descriptor", "No subject.env or subject.env.example file exists")
          return report
        end

        if File.basename(env_path) == "subject.env"
          descriptor_stat = File.lstat(env_path)
          unless descriptor_stat.file? && !descriptor_stat.symlink? &&
                 descriptor_stat.uid == Process.uid && descriptor_stat.nlink == 1 &&
                 (descriptor_stat.mode & 0o077).zero? &&
                 (descriptor_stat.mode & 0o400).positive?
            fail_check(
              report,
              "subject_descriptor_permissions",
              "Private subject.env must be a regular, current-user-owned, singly-linked, owner-only readable file"
            )
            return report
          end
        end

        env = read_env(env_path, report)
        report["descriptor"] = File.basename(env_path)
        report["trigger"] = env["TRIGGER"]
        report["model"] = env["MODEL"]
        validate_descriptor(env, report, directory)

        plan_path = File.join(directory, "train.yaml")
        if File.file?(plan_path) && !File.symlink?(plan_path)
          validate_training_plan(plan_path, directory, env, report)
        elsif File.file?(File.join(directory, "prepare.rb")) && !File.symlink?(File.join(directory, "prepare.rb"))
          block(report, "preparation_only", "A local preparation script exists; no executable training plan is declared")
        else
          block(report, "training_plan_missing", "No train.yaml or local preparation script is present")
        end

        report["training_ready"] = report["state"] == "PASS" && report["blockers"].empty?
        report["training_readiness"] = report["training_ready"] ? "READY_FOR_OPERATOR_REVIEW" : "BLOCKED"
        report
      rescue Psych::Exception, JSON::ParserError, SystemCallError, IOError, ArgumentError, TypeError => error
        {
          "subject" => subject,
          "state" => "FAIL",
          "training_ready" => false,
          "training_readiness" => "BLOCKED",
          "checks" => [],
          "blockers" => [],
          "warnings" => [],
          "errors" => ["#{error.class}: #{error.message}"],
        }
      end

      private

      def read_env(path, report)
        raise ArgumentError, "subject descriptor exceeds 64 KB" if File.size(path) > 65_536

        values = {}
        File.foreach(path).with_index(1) do |line, number|
          stripped = line.strip
          next if stripped.empty? || stripped.start_with?("#")

          match = /\A([A-Z][A-Z0-9_]*)=(.*)\z/.match(stripped)
          unless match
            fail_check(report, "subject_descriptor_syntax", "#{File.basename(path)}:#{number} is not KEY=value")
            next
          end

          key, value = match.captures
          if key.match?(/TOKEN|API_KEY|SECRET|PASSWORD|CREDENTIAL/i)
            fail_check(report, "credential_in_subject_descriptor", "#{key} must come from a private runtime secret source")
            next
          end
          unless ENV_KEYS.include?(key)
            fail_check(report, "unknown_subject_field", "Unsupported subject field #{key.inspect}")
            next
          end
          if values.key?(key)
            fail_check(report, "duplicate_subject_field", "#{key} is declared more than once")
            next
          end

          value = value.strip
          if value.length >= 2 && ((value.start_with?('"') && value.end_with?('"')) ||
                                   (value.start_with?("'") && value.end_with?("'")))
            value = value[1...-1]
          end
          values[key] = value
        end
        values
      end

      def validate_descriptor(env, report, directory)
        trigger = env["TRIGGER"].to_s
        if trigger.match?(/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/)
          pass_check(report, "trigger_word", "Subject trigger is a simple, non-empty token")
        else
          fail_check(report, "trigger_word", "TRIGGER must be a 1–64 character alphanumeric token")
        end

        model = env["MODEL"].to_s
        if model.match?(/\A[a-zA-Z0-9_.-]{1,96}\z/)
          pass_check(report, "model_directory", "MODEL is safe as a local manifest directory")
        else
          fail_check(report, "model_directory", "MODEL must be a simple local directory name")
        end

        descriptor = env["DESCRIPTOR"].to_s.strip
        if descriptor.empty?
          fail_check(report, "subject_descriptor_text", "DESCRIPTOR is empty")
        else
          pass_check(report, "subject_descriptor_text", "A descriptive prompt anchor is present")
        end

        destination = env["REPLICATE_DESTINATION"].to_s.strip
        if destination.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/)
          pass_check(report, "replicate_training_destination", "A private owner/model training destination is configured")
        elsif destination.empty?
          block(report, "replicate_training_destination", "REPLICATE_DESTINATION must name a private owner/model destination")
        else
          fail_check(report, "replicate_training_destination", "REPLICATE_DESTINATION must be owner/model without a version")
        end

        if model.match?(/\A[a-zA-Z0-9_.-]{1,96}\z/)
          weights_directory = File.join(directory, "weights")
          model_directory = File.join(weights_directory, model)
          manifest = File.join(model_directory, "replicate_training.json")
          if [weights_directory, model_directory, manifest].any? { |candidate| File.symlink?(candidate) }
            fail_check(report, "replicate_manifest_path", "Local training manifest path contains a symlink")
            return
          end
          if File.file?(manifest)
            private_directories = [directory, weights_directory, model_directory]
            insecure_directories = private_directories.filter_map do |candidate|
              stat = File.lstat(candidate)
              candidate unless stat.directory? && !stat.symlink? &&
                               stat.uid == Process.uid && (stat.mode & 0o077).zero?
            rescue SystemCallError
              candidate
            end
            if insecure_directories.any?
              fail_check(
                report,
                "replicate_manifest_permissions",
                "Private training manifest directories must be real, current-user-owned and owner-only (0700): #{insecure_directories.map { |item| File.basename(item) }.join(", ")}"
              )
              return
            end

            manifest_stat = File.lstat(manifest)
            unless manifest_stat.file? && !manifest_stat.symlink? &&
                   manifest_stat.uid == Process.uid && manifest_stat.nlink == 1 &&
                   (manifest_stat.mode & 0o077).zero?
              fail_check(
                report,
                "replicate_manifest_permissions",
                "Private training manifest must be a regular, current-user-owned, singly-linked owner-only (0600) file"
              )
              return
            end

            resolved_manifest = File.realpath(manifest)
            unless inside?(resolved_manifest, File.realpath(directory))
              fail_check(report, "replicate_manifest_scope", "Local training manifest resolves outside this subject's private directory")
              return
            end
            raise ArgumentError, "training manifest exceeds 64 KB" if manifest_stat.size > 65_536

            data = JSON.parse(File.read(manifest, encoding: "UTF-8"))
            version = data["version"].to_s
            if version.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}:[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/)
              if data["status"] == "TRAINED_NEEDS_LIKENESS_REVIEW" || data["likeness_review_required"] == true
                report["warnings"] << "Pinned model exists but is awaiting human likeness review"
              end
              pass_check(report, "replicate_version_pin", "Local training manifest pins an immutable Replicate version")
            else
              fail_check(report, "replicate_training_manifest", "Local training manifest does not contain a pinned owner/model:version")
            end
          end
        end

        remote = env["REPLICATE_MODEL"].to_s.strip
        return if remote.empty?

        if remote.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}:[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/)
          pass_check(report, "replicate_version_pin", "REPLICATE_MODEL pins an immutable model version")
        else
          fail_check(report, "replicate_model_reference", "REPLICATE_MODEL must be owner/model:version; use REPLICATE_DESTINATION for new training")
        end
      end

      def validate_training_plan(path, directory, env, report)
        raise ArgumentError, "training config exceeds #{MAX_CONFIG_BYTES} bytes" if File.size(path) > MAX_CONFIG_BYTES

        document = YAML.safe_load(
          File.read(path, encoding: "UTF-8"),
          permitted_classes: [], permitted_symbols: [], aliases: false
        )
        raise ArgumentError, "train.yaml root must be a mapping" unless document.is_a?(Hash)
        raise ArgumentError, "train.yaml schema must be 1" unless document["schema"] == TRAINING_STANDARD.fetch("schema")
        subject = File.basename(directory)
        raise ArgumentError, "train.yaml subject must match #{subject}" unless document["subject"] == subject

        replicate = TRAINING_STANDARD.fetch("replicate")
        trigger = document["trigger_word"].to_s
        unless trigger == env["TRIGGER"] && trigger.match?(/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/)
          fail_check(report, "trainer_trigger_matches_subject", "train.yaml trigger_word must exactly match subject.env TRIGGER")
        else
          pass_check(report, "trainer_trigger_matches_subject", "Training trigger matches the subject descriptor")
        end

        plan_destination_env = document["destination_env"].to_s
        unless plan_destination_env == "REPLICATE_DESTINATION"
          fail_check(report, "training_destination_contract", "train.yaml destination_env must be REPLICATE_DESTINATION")
        else
          pass_check(report, "training_destination_contract", "Training destination comes from the private subject environment")
        end

        model_directory = document["model_directory"].to_s
        unless model_directory == env["MODEL"] && model_directory.match?(/\A[a-zA-Z0-9_.-]{1,96}\z/)
          fail_check(report, "training_model_directory", "train.yaml model_directory must match subject.env MODEL")
        else
          pass_check(report, "training_model_directory", "Private candidate weights have one stable subject directory")
        end

        dataset = document["dataset"]
        unless dataset.is_a?(Hash)
          block(report, "dataset_config", "train.yaml dataset must be a mapping")
          return
        end
        expected_dataset = TRAINING_STANDARD.fetch("dataset")
        dataset_path = dataset["path"].to_s.strip
        if dataset_path != expected_dataset.fetch("path")
          fail_check(report, "dataset_path_contract", "dataset.path must equal #{expected_dataset.fetch("path")}")
          return
        end
        unless dataset["caption_ext"] == expected_dataset.fetch("caption_ext")
          fail_check(report, "dataset_caption_contract", "dataset.caption_ext must equal #{expected_dataset.fetch("caption_ext")}")
          return
        end

        resolved = File.expand_path(dataset_path, directory)
        unless inside?(resolved, directory)
          fail_check(report, "dataset_path_scope", "Dataset path must remain inside this subject's private directory")
          return
        end
        # A declared plan that points its dataset at a symlink violates the
        # dataset path contract: that is a FAIL (existing artifact, wrong
        # shape), not the absence class a missing dataset is.
        if File.symlink?(resolved)
          fail_check(report, "dataset_path", "Configured dataset directory is a symlink")
          return
        end
        unless File.directory?(resolved) && File.readable?(resolved)
          block(report, "dataset_path", "Configured dataset directory is missing or unreadable")
          return
        end

        directory_stat = File.lstat(resolved)
        unless directory_stat.directory? && directory_stat.uid == Process.uid && (directory_stat.mode & 0o077).zero?
          fail_check(report, "dataset_permissions", "Training dataset directory must be owned by the current user and owner-only (0700)")
          return
        end

        real = File.realpath(resolved)
        unless inside?(real, File.realpath(directory))
          fail_check(report, "dataset_path_scope", "Dataset resolves outside this subject's private directory")
          return
        end

        insecure_entries = []
        images = Dir.children(real).select do |name|
          next false unless IMAGE_EXTENSIONS.include?(File.extname(name).downcase)

          image_path = File.join(real, name)
          stat = File.lstat(image_path)
          unless stat.file? && !stat.symlink? && stat.uid == Process.uid && stat.nlink == 1 && (stat.mode & 0o077).zero?
            insecure_entries << name
            next false
          end
          true
        rescue SystemCallError
          insecure_entries << name
          false
        end
        if insecure_entries.any?
          fail_check(report, "dataset_image_permissions", "Training images must be regular, singly-linked, owner-only (0600) files: #{insecure_entries.first(5).join(", ")}")
          return
        end

        captions = images.filter_map do |name|
          caption = File.join(real, "#{File.basename(name, File.extname(name))}.#{expected_dataset.fetch("caption_ext")}")
          problem = caption_problem(caption, env["TRIGGER"])
          [name, problem] if problem
        end
        missing = captions.select { |_name, problem| problem == :missing }
        too_large = captions.select { |_name, problem| problem == :too_large }
        unreadable = captions.select { |_name, problem| %i[unreadable invalid_encoding].include?(problem) }
        triggerless = captions.select { |_name, problem| problem == :trigger_missing }

        minimum = TRAINING_STANDARD.fetch("quality").fetch("min_images")
        maximum = TRAINING_STANDARD.fetch("quality").fetch("max_images")
        if images.length < minimum
          block(report, "dataset_image_count", "Dataset has #{images.length} images; at least #{minimum} are required")
        elsif images.length > maximum
          block(report, "dataset_image_count", "Dataset has #{images.length} images; no more than #{maximum} are allowed")
        elsif missing.any?
          block(report, "dataset_captions", "Missing same-basename captions for: #{missing.first(5).map(&:first).join(", ")}")
        elsif unreadable.any?
          block(report, "dataset_captions_unreadable", "Unreadable or invalid UTF-8 captions for: #{unreadable.first(5).map(&:first).join(", ")}")
        elsif too_large.any?
          block(report, "dataset_caption_size", "Captions exceed #{MAX_CAPTION_BYTES} bytes for: #{too_large.first(5).map(&:first).join(", ")}")
        elsif triggerless.any?
          block(report, "dataset_caption_trigger", "Captions must contain exact trigger #{env["TRIGGER"].inspect}: #{triggerless.first(5).map(&:first).join(", ")}")
        else
          pass_check(report, "dataset_integrity", "#{images.length} owner-only images have matching captions with the subject trigger")
        end
      end

      def caption_problem(path, trigger)
        return :missing unless File.file?(path) && !File.symlink?(path) && File.readable?(path)

        stat = File.lstat(path)
        return :unreadable unless stat.file? && stat.uid == Process.uid && stat.nlink == 1 && (stat.mode & 0o077).zero?
        return :too_large if stat.size > MAX_CAPTION_BYTES

        caption = File.read(path, encoding: "UTF-8")
        return :invalid_encoding unless caption.valid_encoding?

        token = trigger.to_s
        return :trigger_missing unless token.match?(/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/)

        boundary = /(?:\A|[^A-Za-z0-9_-])#{Regexp.escape(token)}(?:\z|[^A-Za-z0-9_-])/i
        caption.match?(boundary) ? nil : :trigger_missing
      rescue SystemCallError, IOError, EncodingError
        :unreadable
      end

      def positive_integer?(value)
        value.is_a?(Integer) && value.positive?
      end

      def inside?(path, root)
        expanded = File.expand_path(path)
        base = File.expand_path(root)
        expanded.start_with?("#{base}#{File::SEPARATOR}")
      end

      def pass_check(report, id, detail)
        report["checks"] << { "id" => id, "state" => "PASS", "detail" => detail }
      end

      def block(report, id, detail)
        report["blockers"] << { "id" => id, "detail" => detail }
      end

      def fail_check(report, id, detail)
        report["state"] = "FAIL"
        report["blockers"] << { "id" => id, "detail" => detail }
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "optparse"
  require_relative "../replicate/interactive"

  options = {}
  wizard = Studio::Interactive.new
  if ARGV.empty? && wizard.tty?
    # No arguments in a terminal: ask, rather than require a remembered flag.
    subjects = Dir.children(Studio::Lora::Validator::ROOT).select do |name|
      Studio::Lora::Validator::SUBJECT_NAME.match?(name) &&
        File.directory?(File.join(Studio::Lora::Validator::ROOT, name))
    end.sort
    choice = wizard.choose("Which subject?", [["All subjects", :all], *subjects.map { |s| [s, s] }])
    options[:subject] = choice unless choice == :all
    options[:json] = wizard.confirm("Print the full JSON report?", default: false)
  else
    OptionParser.new do |parser|
      parser.banner = "Usage: ruby STUDIO/lora/validate.rb [--subject NAME] [--json]"
      parser.on("--subject NAME", "Validate one subject directory") { |value| options[:subject] = value }
      parser.on("--json", "Print the complete machine-readable report") { options[:json] = true }
      parser.on("-h", "--help", "Show this help") { puts parser; exit 0 }
    end.parse!
  end

  validator = Studio::Lora::Validator.new
  report = options[:subject] ? {
    "schema" => "studio.lora.validation.v1",
    "read_only" => true,
    "provider_calls" => 0,
    "subject_count" => 1,
    "subjects" => [validator.validate_subject(options[:subject])]
  } : validator.validate_all

  if options[:json]
    puts JSON.pretty_generate(report)
  else
    report.fetch("subjects").each do |subject|
      puts "lora0: #{subject['subject']} state=#{subject['state']} training_ready=#{subject['training_ready']}"
      subject.fetch("blockers").each { |item| puts "  BLOCKED #{item['id']}: #{item['detail']}" }
      subject.fetch("warnings").each { |item| puts "  WARN #{item}" }
    end
  end

  exit(report.fetch("subjects").any? { |subject| subject["state"] == "FAIL" } ? 1 :
       report.fetch("subjects").any? { |subject| !subject["training_ready"] } ? 2 : 0)
end
