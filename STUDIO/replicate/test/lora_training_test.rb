# frozen_string_literal: true

require_relative "minitest_helper"
require "tmpdir"
require_relative "../../lora/train"

class TestStudioLoraTrainingRunner < Minitest::Test
  def test_preflight_failure_stops_before_any_provider_call
    validator = Object.new
    validator.define_singleton_method(:validate_subject) do |_subject|
      { "training_ready" => false, "blockers" => [{ "detail" => "private training consent is missing" }] }
    end
    client = Object.new
    %i[ensure_private_model! upload_zip train_lora].each do |method|
      client.define_singleton_method(method) do |*|
        flunk "provider must not be called before complete preflight"
      end
    end

    runner = Studio::Lora::Training::Runner.new(client:, validator:, root: Dir.pwd)
    error = assert_raises(Studio::Lora::Training::Error) do
      runner.run(subjects: ["johann"], approve_spend_usd: "5.00")
    end

    assert_match(/consent is missing/, error.message)
  end

  def test_unknown_and_duplicate_subjects_are_refused
    runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root: Dir.pwd)

    assert_raises(ArgumentError) { runner.send(:normalize_subjects, ["johann", "johann"]) }
    assert_raises(ArgumentError) { runner.send(:normalize_subjects, ["unknown"]) }
  end

  def test_training_batch_requires_distinct_private_destinations_before_provider_calls
    client = Object.new
    client.define_singleton_method(:ensure_private_model!) do |_destination|
      flunk "duplicate destinations must block before provider calls"
    end
    runner = Studio::Lora::Training::Runner.new(client:, validator: Object.new, root: Dir.pwd)
    runner.define_singleton_method(:prepare_subject!) do |subject|
      { "subject" => subject, "destination" => "owner/shared-model" }
    end

    error = assert_raises(Studio::Lora::Training::Error) do
      runner.run(subjects: %w[johann ragnhild], approve_spend_usd: "5.00")
    end
    assert_match(/distinct private Replicate destination/, error.message)
  end

  def test_prepare_subject_reads_the_canonical_fast_flux_plan_and_private_destination
    Dir.mktmpdir("studio-lora-package-") do |root|
      subject = File.join(root, "johann")
      dataset = File.join(subject, "dataset")
      FileUtils.mkdir_p(dataset, mode: 0o700)
      File.chmod(0o700, subject)
      12.times do |index|
        write_private(File.join(dataset, "portrait-#{index}.jpg"), "synthetic image")
        write_private(File.join(dataset, "portrait-#{index}.txt"), "johann_lora portrait #{index}")
      end
      File.write(File.join(subject, "train.yaml"), YAML.dump({
        "schema" => 1,
        "subject" => "johann",
        "trigger_word" => "johann_lora",
        "dataset" => { "path" => "dataset", "caption_ext" => "txt" },
        "destination_env" => "REPLICATE_DESTINATION",
        "model_directory" => "johann",
      }), mode: "w", perm: 0o600)

      validator = Object.new
      validator.define_singleton_method(:validate_subject) do |_name|
        { "training_ready" => true, "blockers" => [] }
      end
      configuration = {
        "REPLICATE_DESTINATION" => "owner/johann-private",
        "MODEL" => "johann",
      }
      fake_picture = Object.new
      fake_picture.define_singleton_method(:subject_configuration) do |action:|
        raise "wrong consent action" unless action == :training
        configuration
      end
      runner = Studio::Lora::Training::Runner.new(client: Object.new, validator:, root:)
      runner.define_singleton_method(:build_training_zip) do |name, directory, digest|
        raise "wrong subject" unless name == "johann"
        raise "wrong dataset directory" unless directory == dataset
        "zip:#{digest}"
      end

      package = Studio::Visual::IdeaPicture.stub(:new, ->(**_arguments) { fake_picture }) do
        runner.send(:prepare_subject!, "johann")
      end

      standard = Studio::Lora::Training::STANDARD.fetch("replicate")
      assert_equal "owner/johann-private", package.fetch("destination")
      assert_equal "johann_lora", package.fetch("trigger_word")
      assert_equal standard.fetch("training_steps"), package.fetch("training_steps")
      assert_equal standard.fetch("lora_type"), package.fetch("lora_type")
      assert_equal standard.fetch("seed"), package.fetch("seed")
      assert_match(/\A[0-9a-f]{64}\z/, package.fetch("dataset_sha256"))
    end
  end

  def write_private(path, contents)
    File.write(path, contents, mode: "w", perm: 0o600)
    File.chmod(0o600, path)
  end

  def test_candidate_manifest_is_private_and_explicitly_unapproved
    Dir.mktmpdir("studio-lora-manifest-") do |root|
      subject_directory = File.join(root, "johann")
      cache = File.join(subject_directory, ".cache")
      FileUtils.mkdir_p(cache, mode: 0o700)
      File.chmod(0o700, subject_directory)
      File.chmod(0o700, cache)
      runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root:)
      package = {
        "subject" => "johann", "subject_directory" => subject_directory,
        "model_directory" => "johann", "dataset_sha256" => "a" * 64,
        "trigger_word" => "johann_lora", "training_steps" => 1000, "lora_type" => "subject", "seed" => 42
      }

      path = runner.send(:write_candidate_manifest, package, "owner/johann:version123", { "id" => "training123" }, billing: { "cost_status" => "CALCULATED_FROM_PROVIDER_PREDICT_TIME_NOT_INVOICE", "calculated_cost_usd" => "1.464000" })
      document = JSON.parse(File.read(path))
      assert_equal "TRAINED_NEEDS_LIKENESS_REVIEW", document.fetch("status")
      assert_equal true, document.fetch("likeness_review_required")
      assert_equal "owner/johann:version123", document.fetch("version")
      assert_equal 1000, document.fetch("training_steps")
      assert_equal "subject", document.fetch("lora_type")
      assert_equal 42, document.fetch("seed")
      assert_equal "CALCULATED_FROM_PROVIDER_PREDICT_TIME_NOT_INVOICE", document.dig("billing", "cost_status")
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  def test_candidate_manifest_preserves_the_previous_private_version
    Dir.mktmpdir("studio-lora-manifest-backup-") do |root|
      subject_directory = File.join(root, "ragnhild")
      cache = File.join(subject_directory, ".cache")
      model_directory = File.join(subject_directory, "weights", "ragnhild")
      FileUtils.mkdir_p(cache, mode: 0o700)
      FileUtils.mkdir_p(model_directory, mode: 0o700)
      [subject_directory, cache, File.join(subject_directory, "weights"), model_directory].each { |path| File.chmod(0o700, path) }
      old_path = File.join(model_directory, "replicate_training.json")
      old = JSON.generate("version" => "owner/ragnhild:oldversion")
      File.write(old_path, old, mode: "w", perm: 0o600)
      runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root:)
      package = {
        "subject" => "ragnhild", "subject_directory" => subject_directory,
        "model_directory" => "ragnhild", "dataset_sha256" => "b" * 64,
        "trigger_word" => "ragnhild", "training_steps" => 1000, "lora_type" => "subject", "seed" => 42
      }

      runner.send(:write_candidate_manifest, package, "owner/ragnhild:newversion", { "id" => "training456" }, billing: { "cost_status" => "NOT_REPORTED_BY_PROVIDER" })
      backups = Dir.glob(File.join(cache, "previous-training-*.json"))
      assert_equal 1, backups.length
      assert_equal old, File.read(backups.first)
      assert_equal "owner/ragnhild:newversion", JSON.parse(File.read(old_path)).fetch("version")
    end
  end

  def test_unsupported_timeout_is_rejected_before_subject_packaging
    runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root: Dir.pwd)
    runner.define_singleton_method(:prepare_subject!) { |_subject| flunk "invalid timeout must be rejected before packaging" }

    error = assert_raises(ArgumentError) do
      runner.run(subjects: ["johann"], timeout: 86_401, approve_spend_usd: "5.00")
    end
    assert_match(/between 1 and 86400 seconds/, error.message)
  end

  def test_training_requires_a_minimum_approved_compute_window_before_preflight
    runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root: Dir.pwd)
    runner.define_singleton_method(:prepare_subject!) { |_subject| flunk "budget must be rejected before local packaging" }

    error = assert_raises(Studio::Lora::Training::Error) do
      runner.run(subjects: ["johann"], approve_spend_usd: "0.50")
    end
    assert_match(/too small for the minimum/, error.message)
  end

  def test_batch_budget_is_shared_and_each_training_gets_a_remaining_time_ceiling
    Dir.mktmpdir("studio-lora-budget-") do |root|
      client = Object.new
      client.define_singleton_method(:ensure_private_model!) { |_destination| true }
      runner = Studio::Lora::Training::Runner.new(client:, validator: Object.new, root:)
      runner.define_singleton_method(:prepare_subject!) do |subject|
        { "subject" => subject, "destination" => "owner/#{subject}" }
      end
      timeouts = []
      assertions = self
      runner.define_singleton_method(:train_subject!) do |_client, package, timeout:, billing_rate:, approved_budget_usd:, reserved_timeout_seconds:|
        timeouts << timeout
        assertions.assert_equal billing_rate, Studio::Lora::Training::BILLING_RATE
        assertions.assert_equal approved_budget_usd, BigDecimal("4.50")
        assertions.assert_equal timeout, reserved_timeout_seconds
        {
          "subject" => package.fetch("subject"),
          "status" => "TRAINED_NEEDS_LIKENESS_REVIEW",
          "provider_request_dispatched" => true,
          "billing" => {
            "cost_status" => "CALCULATED_FROM_PROVIDER_PREDICT_TIME_NOT_INVOICE",
            "provider_compute_seconds" => "120.000000",
            "calculated_cost_usd" => "1.464000",
          }
        }
      end

      report = runner.run(subjects: %w[johann ragnhild merethe], approve_spend_usd: "4.50")
      assert_equal [358, 238, 118], timeouts
      assert_equal "TRAINED_NEEDS_LIKENESS_REVIEW", report.fetch("status")
      assert_equal "4.392000", report.dig("spend", "calculated_cost_usd_not_invoice")
      assert_equal "0.108000", report.dig("spend", "remaining_approved_usd")
      assert_equal "CLIENT_SIDE_TIMEOUT_AND_CANCEL_NOT_A_PROVIDER_HARD_CAP", report.dig("spend", "guard_kind")
      assert_equal ".cache/training-spend.jsonl", report.fetch("spend_receipt")
    end
  end

  def test_unreported_training_cost_stops_the_remaining_paid_batch
    Dir.mktmpdir("studio-lora-unknown-cost-") do |root|
      client = Object.new
      client.define_singleton_method(:ensure_private_model!) { |_destination| true }
      runner = Studio::Lora::Training::Runner.new(client:, validator: Object.new, root:)
      runner.define_singleton_method(:prepare_subject!) do |subject|
        { "subject" => subject, "destination" => "owner/#{subject}" }
      end
      calls = []
      runner.define_singleton_method(:train_subject!) do |_client, package, **_options|
        calls << package.fetch("subject")
        {
          "subject" => package.fetch("subject"),
          "status" => "FAILED",
          "provider_request_dispatched" => true,
          "billing" => { "cost_status" => "NOT_REPORTED_BY_PROVIDER" }
        }
      end

      report = runner.run(subjects: %w[johann ragnhild merethe], approve_spend_usd: "5.00")
      assert_equal ["johann"], calls
      assert_equal "SPEND_UNVERIFIED", report.fetch("status")
      assert_equal "SKIPPED_SPEND_UNVERIFIED", report.fetch("results")[1].fetch("status")
      assert_equal "SKIPPED_SPEND_UNVERIFIED", report.fetch("results")[2].fetch("status")
      ledger = File.join(root, ".cache", "training-spend.jsonl")
      record = JSON.parse(File.read(ledger))
      assert_equal "SPEND_UNVERIFIED", record.fetch("status")
      assert_equal "NOT_REPORTED_BY_PROVIDER", record.dig("results", 0, "billing", "cost_status")
    end
  end

  def test_provider_predict_time_is_converted_to_a_calculated_cost_not_an_invoice
    runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root: Dir.pwd)
    receipt = runner.send(:training_cost_receipt, { "metrics" => { "predict_time" => 120.0, "total_time" => 150.0 } }, Studio::Lora::Training::BILLING_RATE)

    assert_equal "CALCULATED_FROM_PROVIDER_PREDICT_TIME_NOT_INVOICE", receipt.fetch("cost_status")
    assert_equal "120.000000", receipt.fetch("provider_compute_seconds")
    assert_equal "1.464000", receipt.fetch("calculated_cost_usd")
    assert_equal "0.0122", receipt.fetch("rate_usd_per_second")
  end

  def test_calculated_cost_rounds_up_to_avoid_understating_provider_usage
    runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root: Dir.pwd)
    receipt = runner.send(:training_cost_receipt, { "metrics" => { "predict_time" => 0.0001 } }, Studio::Lora::Training::BILLING_RATE)

    assert_equal "0.000002", receipt.fetch("calculated_cost_usd")
  end

  def test_confirmed_cancelled_training_keeps_terminal_compute_cost
    client = Object.new
    client.define_singleton_method(:upload_zip) { |_path, subject:| "https://upload.invalid/#{subject}.zip" }
    client.define_singleton_method(:train_lora) do |*_arguments, **_options|
      {
        "status" => "canceled",
        "metrics" => { "predict_time" => 80.0 },
        "client_cancel_confirmed" => true
      }
    end
    runner = Studio::Lora::Training::Runner.new(client:, validator: Object.new, root: Dir.pwd)
    package = {
      "subject" => "johann",
      "zip_path" => "/private/johann.zip",
      "destination" => "owner/johann",
      "trigger_word" => "johann_lora",
      "training_steps" => 1000,
      "lora_type" => "subject",
      "seed" => 42,
      "dataset_sha256" => "a" * 64
    }

    result = runner.send(
      :train_subject!, client, package,
      timeout: 400, billing_rate: Studio::Lora::Training::BILLING_RATE,
      approved_budget_usd: BigDecimal("5"), reserved_timeout_seconds: 400
    )

    assert_equal "FAILED", result.fetch("status")
    assert_equal true, result.fetch("provider_cancellation_confirmed")
    assert_equal "CALCULATED_FROM_PROVIDER_PREDICT_TIME_NOT_INVOICE", result.dig("billing", "cost_status")
    assert_equal "0.976000", result.dig("billing", "calculated_cost_usd")
  end

  def test_cli_refuses_paid_training_without_a_spend_approval
    assert_equal 2, Studio::Lora::Training.run_cli(["--subject", "johann"])
  end

  def test_private_spend_ledger_records_partial_costs_without_provider_error_text
    Dir.mktmpdir("studio-lora-spend-ledger-") do |root|
      cache = File.join(root, ".cache")
      Dir.mkdir(cache, 0o700)
      runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root:)
      runner.send(:prepare_spend_ledger!)
      report = {
        "status" => "SPEND_UNVERIFIED",
        "spend" => { "approved_batch_budget_usd" => "5.0", "status" => "SPEND_UNVERIFIED" },
        "results" => [{
          "subject" => "johann",
          "status" => "FAILED",
          "training_id" => "training_123",
          "provider_request_dispatched" => true,
          "billing" => { "cost_status" => "NOT_REPORTED_BY_PROVIDER" },
          "error" => "must not enter the receipt; includes a signed upload URL",
        }]
      }

      path = runner.send(:append_spend_receipt!, report, subjects: ["johann"])
      record = JSON.parse(File.read(path))

      assert_equal "studio.lora.training_spend.v1", record.fetch("schema")
      assert_equal "SPEND_UNVERIFIED", record.fetch("status")
      assert_equal "NOT_REPORTED_BY_PROVIDER", record.dig("results", 0, "billing", "cost_status")
      refute_includes File.read(path), "signed upload URL"
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal 1, File.readlines(path).length
    end
  end

  def test_spend_lock_refuses_symlink_path
    Dir.mktmpdir("studio-lora-lock-symlink-") do |root|
      cache = File.join(root, ".cache")
      Dir.mkdir(cache, 0o700)
      target = File.join(root, "outside.lock")
      File.write(target, "keep")
      File.symlink(target, File.join(cache, "training-spend.lock"))
      runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root:)

      assert_raises(SystemCallError) { runner.send(:with_training_lock) { flunk "symlinked lock must not be acquired" } }
      assert_equal "keep", File.read(target)
    end
  end

  def test_private_spend_ledger_refuses_symlink_before_append
    Dir.mktmpdir("studio-lora-spend-symlink-") do |root|
      cache = File.join(root, ".cache")
      Dir.mkdir(cache, 0o700)
      target = File.join(root, "outside.jsonl")
      File.write(target, "keep")
      File.symlink(target, File.join(cache, "training-spend.jsonl"))
      runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root:)

      assert_raises(Studio::Lora::Training::Error) { runner.send(:prepare_spend_ledger!) }
      assert_equal "keep", File.read(target)
    end
  end

  def test_all_three_subjects_are_the_default_batch
    assert_equal %w[johann ragnhild merethe], Studio::Lora::Training::SUBJECTS
  end

  def test_canonical_final_render_count_matches_the_four_portrait_release
    assert_equal 4, Studio::Lora::Training::STANDARD.fetch("review").fetch("final_render_count")
  end
end
