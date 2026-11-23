# frozen_string_literal: true

require "stringio"
require_relative "minitest_helper"
require_relative "../../lora/lora"
require_relative "../../lora/photograph"
require_relative "../../lora/selfie_film"

class TestStudioLoraCli < Minitest::Test
  CLI = Studio::Lora::CLI

  def test_validator_flags_are_forwarded_without_the_cli_subcommand
    seen = nil
    status = CLI.stub(:validate_with_flags, ->(arguments) { seen = arguments; 0 }) do
      CLI.run_flags(["validate", "--json", "--subject", "johann"])
    end

    assert_equal 0, status
    assert_equal ["--json", "--subject", "johann"], seen
  end

  def test_legacy_direct_validator_flags_remain_supported
    seen = nil
    status = CLI.stub(:validate_with_flags, ->(arguments) { seen = arguments; 2 }) do
      CLI.run_flags(["--subject", "ragnhild", "--json"])
    end

    assert_equal 2, status
    assert_equal ["--subject", "ragnhild", "--json"], seen
  end

  def test_training_command_delegates_to_the_local_runner
    seen = nil
    status = CLI.stub(:train_command, ->(arguments) { seen = arguments; 0 }) do
      CLI.run_flags(["train", "--all", "--timeout", "7200"])
    end

    assert_equal 0, status
    assert_equal ["--all", "--timeout", "7200"], seen
  end

  def test_quality_api_is_read_only_and_calls_no_provider
    require_relative "../../lora/quality"
    report = {
      "schema" => "studio.lora.quality.v1",
      "read_only" => true,
      "provider_calls" => 0,
      "state" => "BLOCKED",
    }
    Studio::Lora::Quality.stub(:report, ->(subject: nil) {
      assert_nil subject
      report
    }) do
      assert_equal report, CLI.quality_report({})
    end
  end

  def test_film_api_passes_the_selected_inference_profile
    captured = {}
    fake = Object.new
    fake.define_singleton_method(:run_all) do |subjects:, count:, engine:, inference_profile:|
      captured[:subjects] = subjects
      captured[:count] = count
      captured[:engine] = engine
      captured[:inference_profile] = inference_profile
      { "state" => "BLOCKED" }
    end
    Studio::Lora::SelfieFilm.stub(:new, -> { fake }) do
      report = CLI.film_render({ "subject" => "johann", "count" => 2, "inference_profile" => "detail" })
      assert_equal "BLOCKED", report.fetch("state")
    end
    assert_equal ["johann"], captured.fetch(:subjects)
    assert_equal 2, captured.fetch(:count)
    assert_nil captured.fetch(:engine)
    assert_equal "detail", captured.fetch(:inference_profile)
  end

  def test_quality_command_is_reachable_without_a_tty
    seen = nil
    status = CLI.stub(:quality_command, ->(arguments) { seen = arguments; 0 }) do
      CLI.run_flags(["quality", "--json", "--subject", "johann"])
    end

    assert_equal 0, status
    assert_equal ["--json", "--subject", "johann"], seen
  end

  def test_recovery_is_dry_run_when_no_apply_flag_is_given
    seen = nil
    output, error = capture_io do
      CLI.stub(:recovery_command, lambda { |arguments|
        seen = arguments
        { "mode" => "dry_run", "provider_calls" => 0 }
      }) do
        assert_equal 0, CLI.run_flags(["recover"])
      end
    end

    assert_equal [], seen
    assert_includes output, '"mode": "dry_run"'
    assert_empty error
  end

  def test_recovery_passes_explicit_apply_and_subject_arguments_verbatim
    seen = nil
    output, error = capture_io do
      CLI.stub(:recovery_command, lambda { |arguments|
        seen = arguments
        { "mode" => "apply", "provider_calls" => 0 }
      }) do
        assert_equal 0, CLI.run_flags(["recover", "--subject", "johann", "--apply"])
      end
    end

    assert_equal ["--subject", "johann", "--apply"], seen
    assert_includes output, '"mode": "apply"'
    assert_empty error
  end
  def test_photograph_cli_defaults_to_four_images
    options = studio_photograph_options([])

    assert_equal 4, options.fetch(:count)
  end

  def test_photograph_cli_parses_a_named_inference_profile
    options = studio_photograph_options(%w[--inference-profile identity])

    assert_equal "identity", options.fetch(:inference_profile)
  end

  def test_photograph_cli_only_opens_the_wizard_without_explicit_arguments
    assert studio_photograph_interactive?([], tty: true)
    refute studio_photograph_interactive?(%w[--all-subjects --count 4], tty: true)
    refute studio_photograph_interactive?([], tty: false)
  end

  def test_photograph_cli_parses_batch_flags_for_non_tty_automation
    arguments = %w[--all-subjects --count 4]
    options = studio_photograph_options(arguments)

    assert_equal true, options.fetch(:all_subjects)
    assert_equal 4, options.fetch(:count)
    assert_empty arguments
  end

  def test_photograph_api_defaults_to_four_images_for_a_subject
    captured = {}
    fake_series = Object.new
    fake_series.define_singleton_method(:run) do |count:|
      captured[:count] = count
      []
    end

    Studio::Visual::SelfieSeries.stub(:new, lambda { |subject:, engine:, inference_profile:|
      captured[:subject] = subject
      captured[:engine] = engine
      captured[:inference_profile] = inference_profile
      fake_series
    }) do
      result = studio_photograph_actions.fetch("series").call({})
      assert_equal [], result.fetch("rendered")
    end

    assert_equal "ragnhild", captured.fetch(:subject)
    assert_nil captured.fetch(:engine)
    assert_nil captured.fetch(:inference_profile)
    assert_equal 4, captured.fetch(:count)
  end

  def test_all_subjects_preflight_independently_before_any_prediction
    events = []
    factory = lambda do |subject|
      series = Object.new
      series.define_singleton_method(:preflight!) do
        events << [:preflight, subject]
        raise "private consent is missing" if subject == "blocked"
      end
      series.define_singleton_method(:run) do |count:|
        events << [:render, subject, count]
        ["#{subject}_selfie_01.jpg"]
      end
      series
    end

    report = studio_all_subjects_render(
      subjects: %w[ready blocked], count: 1, series_factory: factory
    )

    assert_equal "PARTIAL", report.fetch("status")
    assert_equal ["ready_selfie_01.jpg"], report.fetch("subjects").fetch("ready")
    assert_empty report.fetch("subjects").fetch("blocked")
    assert_equal "RENDERED", report.fetch("subject_status").fetch("ready").fetch("state")
    assert_equal "BLOCKED", report.fetch("subject_status").fetch("blocked").fetch("state")
    assert_match(/private consent is missing/, report.fetch("subject_status").fetch("blocked").fetch("reason"))
    assert_equal [
      [:preflight, "ready"],
      [:preflight, "blocked"],
      [:render, "ready", 1],
    ], events
  end

  def test_all_subjects_reports_blocked_when_no_subject_passes_preflight
    rendered = []
    factory = lambda do |subject|
      series = Object.new
      series.define_singleton_method(:preflight!) { raise "#{subject} consent missing" }
      series.define_singleton_method(:run) { |count:| rendered << subject; [] }
      series
    end

    report = studio_all_subjects_render(
      subjects: %w[first second], count: 1, series_factory: factory
    )

    assert_equal "BLOCKED", report.fetch("status")
    assert_empty rendered
    assert_equal %w[BLOCKED BLOCKED], report.fetch("subject_status").values.map { |item| item.fetch("state") }
  end

end
