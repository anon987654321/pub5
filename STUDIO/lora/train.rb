#!/usr/bin/env ruby
# frozen_string_literal: true

require "bigdecimal"
require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "time"
require "tmpdir"
require "tempfile"
require "yaml"
require_relative "validate"
require_relative "idea_picture"
require_relative "../replicate/client"

module Studio
  module Lora
    module Training
      ROOT = File.expand_path(__dir__).freeze
      SUBJECTS = %w[johann ragnhild merethe].freeze
      STANDARD_PATH = File.join(ROOT, "training_standards.yml").freeze
      STANDARD = YAML.safe_load_file(
        STANDARD_PATH, permitted_classes: [], permitted_symbols: [], aliases: false
      ).freeze
      DEFAULT_TIMEOUT = 14_400
      BILLING = STANDARD.fetch("billing").freeze
      BILLING_RATE = BigDecimal(BILLING.fetch("usd_per_second").to_s).freeze

      class Error < StandardError; end

      class Runner
        def initialize(client: nil, validator: nil, root: ROOT, zip_executable: ENV.fetch("ZIP", "zip"))
          @client = client
          @root = File.expand_path(root)
          @validator = validator || Validator.new(root: @root)
          @zip_executable = zip_executable
        end

        # Every subject is validated and packaged before the first provider call.
        # A single missing permission, image, caption or private setting blocks
        # the whole batch before a paid upload or training request can begin.
        def run(subjects: SUBJECTS, timeout: DEFAULT_TIMEOUT, approve_spend_usd:)
          approved_budget = approved_budget!(approve_spend_usd)
          timeout = Integer(timeout)
          raise ArgumentError, "training timeout must be positive" unless timeout.positive?

          minimum_seconds = BILLING.fetch("minimum_training_seconds")
          margin_seconds = BILLING.fetch("cancellation_margin_seconds")
          maximum_seconds = (approved_budget / BILLING_RATE).floor
          if maximum_seconds < minimum_reserved_seconds(minimum_seconds, margin_seconds)
            raise Error, "approved spend ceiling is too small for the minimum #{minimum_seconds}s training window"
          end

          names = normalize_subjects(subjects)
          packages = names.map { |subject| prepare_subject!(subject) }
          destinations = packages.map { |package| package.fetch("destination") }
          unless destinations.uniq.length == destinations.length
            raise Error, "each subject must have a distinct private Replicate destination"
          end
          client = @client || Studio::ReplicateClient.new

          with_training_lock do
            # Check/create every destination as private before the first dataset
            # ZIP is uploaded. A pre-existing public destination blocks the run.
            packages.each { |package| client.ensure_private_model!(package.fetch("destination")) }

            results = []
            spent = BigDecimal("0")
            measured_seconds = BigDecimal("0")
            spend_state = "MEASURED"
            packages.each_with_index do |package, index|
              remaining = approved_budget - spent
              available_seconds = (remaining / BILLING_RATE).floor - margin_seconds
              job_timeout = [timeout, available_seconds].min

              if job_timeout < minimum_seconds
                results << skipped_result(package, "SKIPPED_BUDGET", "remaining approved spend cannot reserve a useful training window")
                next
              end

              result = train_subject!(
                client, package, timeout: job_timeout, billing_rate: BILLING_RATE,
                approved_budget_usd: approved_budget, reserved_timeout_seconds: job_timeout
              )
              results << result
              next unless result["provider_request_dispatched"]

              billing = result.fetch("billing")
              unless billing["cost_status"] == "CALCULATED_FROM_PROVIDER_PREDICT_TIME_NOT_INVOICE"
                spend_state = "SPEND_UNVERIFIED"
                packages.drop(index + 1).each do |remaining_package|
                  results << skipped_result(
                    remaining_package, "SKIPPED_SPEND_UNVERIFIED",
                    "a prior training request has no terminal provider compute metric"
                  )
                end
                break
              end

              spent += BigDecimal(billing.fetch("calculated_cost_usd"))
              measured_seconds += BigDecimal(billing.fetch("provider_compute_seconds"))
              if spent > approved_budget
                spend_state = "BUDGET_EXCEEDED"
                packages.drop(index + 1).each do |remaining_package|
                  results << skipped_result(remaining_package, "SKIPPED_BUDGET_EXCEEDED",
                                            "measured provider compute exceeded the approved batch ceiling")
                end
                break
              end
            end

            successful = results.length == packages.length &&
                         results.all? { |result| result.fetch("status") == "TRAINED_NEEDS_LIKENESS_REVIEW" }
            status = if spend_state == "BUDGET_EXCEEDED"
                       "BUDGET_EXCEEDED"
                     elsif spend_state == "SPEND_UNVERIFIED"
                       "SPEND_UNVERIFIED"
                     elsif successful
                       "TRAINED_NEEDS_LIKENESS_REVIEW"
                     else
                       "PARTIAL_FAILURE"
                     end
            {
              "status" => status,
              "provider_training_jobs" => results.count { |result| result["provider_request_dispatched"] },
              "spend" => {
                "approved_batch_budget_usd" => decimal_string(approved_budget),
                "rate_usd_per_second" => decimal_string(BILLING_RATE),
                "pricing_hardware" => BILLING.fetch("hardware"),
                "pricing_verified_on" => BILLING.fetch("verified_on"),
                "pricing_source" => BILLING.fetch("source"),
                "maximum_compute_seconds_at_rate" => maximum_seconds,
                "measured_provider_compute_seconds" => decimal_string(measured_seconds),
                "calculated_cost_usd_not_invoice" => decimal_string(spent),
                "remaining_approved_usd" => decimal_string([approved_budget - spent, BigDecimal("0")].max),
                "status" => spend_state
              },
              "results" => results,
              "next_step" => "Compare each candidate model against that subject's approved source photographs. Set LIKELINESS_REVIEWED_VERSION only after human approval."
            }
          end
        end

        private

        def approved_budget!(value)
          amount = BigDecimal(value.to_s)
          raise ArgumentError, "approved spend must be a finite positive USD amount" unless amount.finite? && amount.positive?

          amount
        rescue ArgumentError, TypeError
          raise ArgumentError, "approved spend must be a finite positive USD amount"
        end

        def decimal_string(value)
          value.round(6).to_s("F")
        end

        def minimum_reserved_seconds(minimum, margin)
          minimum + margin
        end

        def skipped_result(package, status, reason)
          {
            "subject" => package.fetch("subject"),
            "status" => status,
            "provider_request_dispatched" => false,
            "reason" => reason
          }
        end

        # Prevent two training batches in this checkout from spending against
        # separate copies of the same local approval at the same time.
        def with_training_lock
          cache = File.join(@root, ".cache")
          secure_directory!(cache)
          path = File.join(cache, "training-spend.lock")
          flags = File::RDWR | File::CREAT
          flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)

          File.open(path, flags, 0o600) do |file|
            stat = File.lstat(path)
            unless stat.file? && !stat.symlink? && stat.uid == Process.uid &&
                   stat.nlink == 1 && (stat.mode & 0o077).zero?
              raise Error, "training spend lock must be a private singly-linked owner file"
            end
            raise Error, "another LoRA training batch holds the spend lock" unless
              file.flock(File::LOCK_EX | File::LOCK_NB)

            begin
              yield
            ensure
              file.flock(File::LOCK_UN)
            end
          end
        end

        def normalize_subjects(subjects)
          names = Array(subjects).map(&:to_s)
          raise ArgumentError, "select at least one subject" if names.empty?
          raise ArgumentError, "unknown or duplicate training subject" unless
            names.uniq == names && (names - SUBJECTS).empty?

          names
        end

        def prepare_subject!(subject)
          report = @validator.validate_subject(subject)
          unless report["training_ready"] == true
            blockers = Array(report["blockers"]).map { |item| item["detail"] || item["id"] }
            raise Error, "#{subject} training preflight blocked: #{blockers.join("; ")}"
          end

          subject_directory = File.join(@root, subject)
          configuration = Studio::Visual::IdeaPicture.new(
            subject:, subjects_root: @root
          ).subject_configuration(action: :training)
          destination = configuration["REPLICATE_DESTINATION"].to_s.strip
          unless destination.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/)
            raise Error, "#{subject}: REPLICATE_DESTINATION in private subject.env must be owner/model"
          end

          model_directory = configuration["MODEL"].to_s.strip
          model_directory = subject if model_directory.empty?
          unless model_directory.match?(/\A[a-zA-Z0-9_.-]{1,96}\z/)
            raise Error, "#{subject}: MODEL in private subject.env must be a simple directory name"
          end

          plan = load_plan(subject_directory)
          raise Error, "#{subject}: training plan subject/schema mismatch" unless
            plan.is_a?(Hash) && plan["schema"] == 1 && plan["subject"] == subject
          raise Error, "#{subject}: plan destination/model directory mismatch" unless
            plan["destination_env"] == "REPLICATE_DESTINATION" && plan["model_directory"] == model_directory

          dataset_plan = plan.fetch("dataset")
          dataset_relative = dataset_plan.fetch("path").to_s
          raise Error, "#{subject}: caption extension differs from the shared standard" unless
            dataset_plan.fetch("caption_ext") == STANDARD.fetch("dataset").fetch("caption_ext")
          dataset = File.expand_path(dataset_relative, subject_directory)
          dataset = private_dataset_directory!(dataset, subject_directory)
          digest = dataset_digest(dataset)
          zip_path = build_training_zip(subject, dataset, digest)

          {
            "subject" => subject,
            "subject_directory" => subject_directory,
            "dataset_sha256" => digest,
            "zip_path" => zip_path,
            "destination" => destination,
            "model_directory" => model_directory,
            "trigger_word" => plan.fetch("trigger_word"),
            "training_steps" => STANDARD.fetch("replicate").fetch("training_steps"),
            "lora_type" => STANDARD.fetch("replicate").fetch("lora_type"),
            "seed" => STANDARD.fetch("replicate").fetch("seed"),
          }
        end

        def load_plan(subject_directory)
          path = File.join(subject_directory, "train.yaml")
          raise Error, "train.yaml is missing or is a symlink" unless File.file?(path) && !File.symlink?(path)
          raise Error, "train.yaml exceeds 1 MB" if File.size(path) > 1_048_576

          YAML.safe_load(File.read(path, encoding: "UTF-8"),
                         permitted_classes: [], permitted_symbols: [], aliases: false)
        rescue Psych::Exception => error
          raise Error, "invalid training plan: #{error.message}"
        end

        def private_dataset_directory!(path, subject_directory)
          raise Error, "dataset directory is missing or is a symlink" unless File.directory?(path) && !File.symlink?(path)

          root = File.realpath(subject_directory)
          real = File.realpath(path)
          raise Error, "dataset resolves outside its private subject directory" unless real.start_with?("#{root}#{File::SEPARATOR}")

          stat = File.lstat(real)
          unless stat.directory? && stat.uid == Process.uid && (stat.mode & 0o077).zero?
            raise Error, "dataset directory must be owner-only (0700)"
          end

          real
        end

        def dataset_digest(directory)
          digest = Digest::SHA256.new
          entries = Dir.children(directory).sort
          raise Error, "dataset is empty" if entries.empty?

          entries.each do |name|
            path = File.join(directory, name)
            stat = File.lstat(path)
            unless stat.file? && !stat.symlink? && stat.uid == Process.uid && stat.nlink == 1 && (stat.mode & 0o077).zero?
              raise Error, "dataset entry must be a singly-linked owner-only regular file: #{name}"
            end

            extension = File.extname(name).downcase
            unless Validator::IMAGE_EXTENSIONS.include?(extension) || extension == ".txt"
              raise Error, "unexpected dataset file type: #{name}"
            end

            digest.update(name)
            digest.update("\0")
            digest.update(stat.size.to_s)
            digest.update("\0")
            File.open(path, "rb") do |file|
              # A while-modifier body references `chunk` before its
              # condition declares the local, which raises NameError; keep
              # the read loop explicit.
              while (chunk = file.read(1024 * 1024))
                digest.update(chunk)
              end
            end
          end
          digest.hexdigest
        end

        def build_training_zip(subject, dataset, digest)
          cache = File.join(@root, subject, ".cache")
          secure_directory!(cache)
          stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")
          target = File.join(cache, "#{subject}_training_#{digest[0, 12]}_#{stamp}.zip")
          entries = Dir.children(dataset).sort.map { |name| "./#{name}" }
          raise Error, "training dataset is empty" if entries.empty?

          Dir.mktmpdir(".#{subject}-training-", cache) do |staging|
            staged = File.join(staging, "training.zip")
            stdout, stderr, status = Open3.capture3(
              @zip_executable, "-q", "-X", staged, *entries, chdir: dataset
            )
            unless status.success? && File.file?(staged) && File.size(staged).positive?
              raise Error, "training ZIP creation failed: #{[stdout, stderr].join(" ").strip}"
            end

            File.chmod(0o600, staged)
            File.rename(staged, target)
          end
          File.chmod(0o600, target)
          target
        rescue Errno::ENOENT
          raise Error, "zip executable not found; install the system zip utility"
        end

        def secure_directory!(path)
          raise Error, "refusing symlink directory: #{path}" if File.symlink?(path)

          FileUtils.mkdir_p(path, mode: 0o700)
          stat = File.lstat(path)
          raise Error, "directory must be owned by the current user" unless stat.directory? && stat.uid == Process.uid
          File.chmod(0o700, path)
        end

        def train_subject!(client, package, timeout:, billing_rate:, approved_budget_usd:, reserved_timeout_seconds:)
          subject = package.fetch("subject")
          provider_request_dispatched = false
          billing = nil
          begin
            upload_url = client.upload_zip(package.fetch("zip_path"), subject:)
            provider_request_dispatched = true
            training = client.train_lora(
              upload_url,
              package.fetch("destination"),
              trigger_word: package.fetch("trigger_word"),
              training_steps: package.fetch("training_steps"),
              lora_type: package.fetch("lora_type"),
              seed: package.fetch("seed"),
              timeout:,
              wait: true,
              subject:
            )
            billing = training_cost_receipt(training, billing_rate).merge(
              "approved_batch_budget_usd" => decimal_string(approved_budget_usd),
              "reserved_timeout_seconds" => reserved_timeout_seconds
            )
            raise Error, "#{subject}: Replicate training did not succeed (#{training["status"]})" unless training["status"] == "succeeded"

            version_id = client.latest_version(package.fetch("destination"))
            raise Error, "#{subject}: Replicate returned an invalid model version" unless version_id.to_s.match?(/\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/)

            full_version = "#{package.fetch("destination")}:#{version_id}"
            manifest = write_candidate_manifest(package, full_version, training, billing:)
            {
              "subject" => subject,
              "status" => "TRAINED_NEEDS_LIKENESS_REVIEW",
              "training_id" => training["id"],
              "model_version" => full_version,
              "manifest" => File.basename(manifest),
              "dataset_sha256" => package.fetch("dataset_sha256"),
              "provider_request_dispatched" => true,
              "billing" => billing
            }
          rescue StandardError => error
            {
              "subject" => subject,
              "status" => "FAILED",
              "error" => "#{error.class}: #{error.message.to_s[0, 500]}",
              "dataset_sha256" => package.fetch("dataset_sha256"),
              "provider_request_dispatched" => provider_request_dispatched,
              "billing" => billing || {
                "cost_status" => (provider_request_dispatched ? "NOT_REPORTED_BY_PROVIDER" : "NOT_REQUESTED"),
                "rate_usd_per_second" => decimal_string(billing_rate),
                "pricing_source" => BILLING.fetch("source")
              }
            }
          end
        end

        def training_cost_receipt(training, rate)
          metrics = training.is_a?(Hash) ? training["metrics"] : nil
          seconds = metrics.is_a?(Hash) ? metrics["predict_time"] : nil
          valid = seconds.is_a?(Numeric) && seconds.finite? && seconds >= 0
          unless valid
            return {
              "cost_status" => "NOT_REPORTED_BY_PROVIDER",
              "provider_compute_seconds" => nil,
              "rate_usd_per_second" => decimal_string(rate),
              "calculated_cost_usd" => nil,
              "pricing_hardware" => BILLING.fetch("hardware"),
              "pricing_verified_on" => BILLING.fetch("verified_on"),
              "pricing_source" => BILLING.fetch("source")
            }
          end

          compute_seconds = BigDecimal(seconds.to_s)
          calculated = (compute_seconds * rate).round(6)
          {
            "cost_status" => "CALCULATED_FROM_PROVIDER_PREDICT_TIME_NOT_INVOICE",
            "provider_compute_seconds" => decimal_string(compute_seconds),
            "rate_usd_per_second" => decimal_string(rate),
            "calculated_cost_usd" => decimal_string(calculated),
            "pricing_hardware" => BILLING.fetch("hardware"),
            "pricing_verified_on" => BILLING.fetch("verified_on"),
            "pricing_source" => BILLING.fetch("source")
          }
        end

        def write_candidate_manifest(package, version, training, billing:)
          subject_directory = package.fetch("subject_directory")
          model_directory = File.join(subject_directory, "weights", package.fetch("model_directory"))
          secure_directory!(File.join(subject_directory, "weights"))
          secure_directory!(model_directory)
          path = File.join(model_directory, "replicate_training.json")
          raise Error, "refusing symlinked training manifest: #{path}" if File.symlink?(path)

          if File.file?(path)
            stat = File.lstat(path)
            unless stat.file? && stat.uid == Process.uid && stat.nlink == 1 && (stat.mode & 0o077).zero?
              raise Error, "existing training manifest must be a private singly-linked regular file"
            end
            previous = File.binread(path)
            previous_name = "previous-training-#{Digest::SHA256.hexdigest(previous)[0, 12]}.json"
            previous_path = File.join(subject_directory, ".cache", previous_name)
            if File.exist?(previous_path) || File.symlink?(previous_path)
              backup_stat = File.lstat(previous_path)
              unless backup_stat.file? && !backup_stat.symlink? && backup_stat.uid == Process.uid &&
                     backup_stat.nlink == 1 && (backup_stat.mode & 0o077).zero?
                raise Error, "existing checkpoint backup must be a private singly-linked regular file"
              end
            else
              File.open(previous_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(previous) }
            end
          elsif File.exist?(path)
            raise Error, "training manifest path is not a regular file"
          end

          standard = STANDARD.fetch("replicate")
          document = {
            "version" => version,
            "trainer" => standard.fetch("trainer"),
            "trainer_version" => standard.fetch("version"),
            "training_id" => training["id"],
            "dataset_sha256" => package.fetch("dataset_sha256"),
            "trigger_word" => package.fetch("trigger_word"),
            "training_steps" => package.fetch("training_steps"),
            "lora_type" => package.fetch("lora_type"),
            "seed" => package.fetch("seed"),
            "billing" => billing,
            "status" => "TRAINED_NEEDS_LIKENESS_REVIEW",
            "likeness_review_required" => true,
            "trained_at" => Time.now.utc.iso8601,
          }

          Tempfile.create([".replicate-training-", ".json"], model_directory) do |file|
            file.chmod(0o600)
            file.write(JSON.pretty_generate(document) + "\n")
            file.flush
            file.fsync
            file.close
            File.rename(file.path, path)
          end
          File.chmod(0o600, path)
          path
        end
      end

      module_function

      def run_cli(argv)
        options = { subjects: SUBJECTS, timeout: DEFAULT_TIMEOUT, approve_spend_usd: nil }
        OptionParser.new do |parser|
          parser.banner = "Usage: ruby STUDIO/lora/train.rb [--all | --subject NAME] --approve-spend-usd USD [--timeout SECONDS]"
          parser.on("--all", "preflight and train Johann, Ragnhild and Merethe sequentially") { options[:subjects] = SUBJECTS }
          parser.on("--subject NAME", "train one subject after its full private preflight") { |value| options[:subjects] = [value] }
          parser.on("--approve-spend-usd USD", "required total spend ceiling for this batch") { |value| options[:approve_spend_usd] = value }
          parser.on("--timeout SECONDS", Integer, "maximum wait per training, further limited by the approved budget") { |value| options[:timeout] = value }
        end.parse!(argv)

        raise Error, "--approve-spend-usd is required before any paid training request" if options[:approve_spend_usd].to_s.strip.empty?
        result = Runner.new.run(
          subjects: options[:subjects], timeout: options[:timeout],
          approve_spend_usd: options[:approve_spend_usd]
        )
        puts JSON.pretty_generate(result)
        result["status"] == "TRAINED_NEEDS_LIKENESS_REVIEW" ? 0 : 1
      rescue Error, ArgumentError, SystemCallError, IOError, Psych::Exception => error
        warn "BLOCKED: #{error.class}: #{error.message}"
        2
      end
    end
  end
end

exit Studio::Lora::Training.run_cli(ARGV) if $PROGRAM_NAME == __FILE__
