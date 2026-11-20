# frozen_string_literal: true

require "stringio"
require_relative "minitest_helper"
require_relative "../lora/lora"

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
end
