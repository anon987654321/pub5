# frozen_string_literal: true

require "json"
require "yaml"

module Studio
  module Lora
    # Read-only audit of subject descriptors and local training plans. This is
    # deliberately not a trainer: it never uploads data, creates a provider
    # model, starts training, or writes into a subject directory.
    class Validator
      ROOT = File.expand_path(__dir__).freeze
      SUBJECT_NAME = /\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\z/.freeze
      ENV_KEYS = %w[SUBJECT MODEL TRIGGER DESCRIPTOR REPLICATE_MODEL].freeze
      IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze
      MINIMUM_IMAGES = 10
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
          "subjects" => subjects
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
          "warnings" => []
        }

        env_path = %w[subject.env subject.env.example].map { |name| File.join(directory, name) }
                                                    .find { |path| File.file?(path) && !File.symlink?(path) }
        unless env_path
          fail_check(report, "subject_descriptor", "No subject.env or subject.env.example file exists")
          return report
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
          "errors" => ["#{error.class}: #{error.message}"]
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

        if model.match?(/\A[a-zA-Z0-9_.-]{1,96}\z/)
          weights_directory = File.join(directory, "weights")
          model_directory = File.join(weights_directory, model)
          manifest = File.join(model_directory, "replicate_training.json")
          if [weights_directory, model_directory, manifest].any? { |path| File.symlink?(path) }
            fail_check(report, "replicate_manifest_path", "Local training manifest path contains a symlink")
            return
          end
          if File.file?(manifest)
            resolved_manifest = File.realpath(manifest)
            unless inside?(resolved_manifest, File.realpath(directory))
              fail_check(report, "replicate_manifest_scope", "Local training manifest resolves outside this subject's private directory")
              return
            end
            raise ArgumentError, "training manifest exceeds 64 KB" if File.size(manifest) > 65_536

            version = JSON.parse(File.read(manifest, encoding: "UTF-8"))["version"].to_s
            if version.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}:[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/)
              pass_check(report, "replicate_version_pin", "Local training manifest pins the Replicate model version")
              return
            end
            fail_check(report, "replicate_training_manifest", "Local training manifest does not contain a pinned owner/model:version")
            return
          end
        end

        remote = env["REPLICATE_MODEL"].to_s.strip
        return if remote.empty?

        if remote.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}:[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/)
          pass_check(report, "replicate_version_pin", "Replicate model reference pins a version")
        elsif remote.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/)
          report["warnings"] << "REPLICATE_MODEL is unpinned; predictions resolve the provider's latest version"
          block(report, "replicate_version_pin", "Pin owner/model:version or supply a local training manifest before treating renders as reproducible")
        else
          fail_check(report, "replicate_model_reference", "REPLICATE_MODEL must be owner/name or owner/name:version")
        end
      end

      def validate_training_plan(path, directory, env, report)
        raise ArgumentError, "training config exceeds #{MAX_CONFIG_BYTES} bytes" if File.size(path) > MAX_CONFIG_BYTES

        document = YAML.safe_load(File.read(path, encoding: "UTF-8"), permitted_classes: [], permitted_symbols: [], aliases: false)
        raise ArgumentError, "train.yaml root must be a mapping" unless document.is_a?(Hash)
        raise ArgumentError, "train.yaml job must be extension" unless document["job"] == "extension"

        config = document["config"]
        raise ArgumentError, "train.yaml config must be a mapping" unless config.is_a?(Hash)

        processes = config["process"]
        raise ArgumentError, "train.yaml config.process must be a non-empty array" unless processes.is_a?(Array) && !processes.empty?

        trainers = processes.select { |entry| entry.is_a?(Hash) && entry["type"] == "sd_trainer" }
        raise ArgumentError, "train.yaml must declare exactly one sd_trainer process" unless trainers.length == 1

        trainer = trainers.first
        trigger = trainer["trigger_word"].to_s
        unless trigger == env["TRIGGER"]
          fail_check(report, "trainer_trigger_matches_subject", "train.yaml trigger_word does not match subject.env TRIGGER")
        else
          pass_check(report, "trainer_trigger_matches_subject", "Training trigger matches the subject descriptor")
        end

        network = trainer["network"]
        unless network.is_a?(Hash) && network["type"] == "lora" && positive_integer?(network["linear"])
          fail_check(report, "lora_network", "Trainer must declare a LoRA network with a positive linear rank")
        else
          pass_check(report, "lora_network", "LoRA network and rank are declared")
        end

        save = trainer["save"]
        unless save.is_a?(Hash) && save["push_to_hub"] == false
          fail_check(report, "private_training_output", "save.push_to_hub must be explicitly false")
        else
          pass_check(report, "private_training_output", "Automatic Hub publication is explicitly disabled")
        end

        training = trainer["train"]
        if training.is_a?(Hash) && positive_integer?(training["steps"])
          pass_check(report, "training_steps", "A positive training step count is configured")
        else
          fail_check(report, "training_steps", "Trainer must declare a positive integer step count")
        end

        datasets = trainer["datasets"]
        unless datasets.is_a?(Array) && datasets.length == 1 && datasets.first.is_a?(Hash)
          block(report, "dataset_config", "Exactly one dataset entry is required for operator review")
          return
        end

        dataset_path = datasets.first["folder_path"].to_s.strip
        if dataset_path.empty?
          block(report, "dataset_path", "datasets[0].folder_path is blank; the profile is a plan, not a ready training run")
          return
        end

        resolved = File.expand_path(dataset_path, directory)
        unless inside?(resolved, directory)
          fail_check(report, "dataset_path_scope", "Dataset path must remain inside this subject's private directory")
          return
        end
        if File.symlink?(resolved) || !File.directory?(resolved) || !File.readable?(resolved)
          block(report, "dataset_path", "Configured dataset directory is missing, unreadable, or a symlink")
          return
        end

        real = File.realpath(resolved)
        unless inside?(real, File.realpath(directory))
          fail_check(report, "dataset_path_scope", "Dataset resolves outside this subject's private directory")
          return
        end

        images = Dir.children(real).select do |name|
          IMAGE_EXTENSIONS.include?(File.extname(name).downcase) &&
            File.file?(File.join(real, name)) && !File.symlink?(File.join(real, name))
        end
        missing_captions = images.reject do |name|
          caption = File.join(real, "#{File.basename(name, File.extname(name))}.txt")
          File.file?(caption) && !File.symlink?(caption) && File.readable?(caption)
        end
        if images.length < MINIMUM_IMAGES
          block(report, "dataset_image_count", "Dataset has #{images.length} readable images; at least #{MINIMUM_IMAGES} are required")
        elsif missing_captions.any?
          block(report, "dataset_captions", "Missing readable .txt captions for: #{missing_captions.first(5).join(', ')}")
        else
          pass_check(report, "dataset_integrity", "#{images.length} images have readable same-basename captions")
        end
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

  options = {}
  OptionParser.new do |parser|
    parser.banner = "Usage: ruby STUDIO/lora/validate.rb [--subject NAME] [--json]"
    parser.on("--subject NAME", "Validate one subject directory") { |value| options[:subject] = value }
    parser.on("--json", "Print the complete machine-readable report") { options[:json] = true }
    parser.on("-h", "--help", "Show this help") { puts parser; exit 0 }
  end.parse!

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
