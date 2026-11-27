# frozen_string_literal: true

require_relative "test_helper"

class TestCliCommandFlags < Minitest::Test
  SOURCE = File.read(File.expand_path("../bin/master", __dir__))
  HELPERS = SOURCE[/^COMMAND_FLAG.*?(?=^# Flags that affect boot)/m] ||
            raise("CLI argument helper source block not found")

  def setup
    host = Object.new
    host.extend(Module.new { def self.status(*, **) = nil })
    host.instance_eval("require 'optparse'; module Master; module Trace; module Dmesg; def self.status(*, **) = nil; end; end; end\n#{HELPERS}", __FILE__, 1)
    @host = host
  end

  def test_runtime_extracts_the_message_once_and_reuses_it
    assert_equal 1, SOURCE.scan(/initial_message_from_argv\(ARGV/).size
    assert_includes SOURCE, "initial_message = initial_message_from_argv(ARGV.dup)"
    assert_includes SOURCE, "goal = initial_message"
    assert_equal 2, SOURCE.scan(/message = initial_message\b/).size
  end

  def test_fix_flags_survive_into_the_message
    argv = ["/fix", "RAILS", "--max-files=25", "--autofix=on"]

    assert_equal "/fix RAILS --max-files=25 --autofix=on", @host.send(:initial_message_from_argv, argv)
  end

  def test_no_critique_survives_into_the_message_without_an_option_error
    argv = ["/fix", "MASTER", "--no-critique"]
    message = nil
    out, err = capture_io { message = @host.method(:initial_message_from_argv).call(argv) }

    assert_equal "/fix MASTER --no-critique", message

    refute_match(/option error/, err + out)
  end

  def test_blockers_survives_into_the_message
    assert_equal "/fix RAILS --blockers", @host.initial_message_from_argv(["/fix", "RAILS", "--blockers"])
  end

  def test_dry_run_is_never_dropped
    argv = ["/fix", "MASTER", "--dry-run", "--no-autofix", "--only=critique"]

    message = @host.method(:initial_message_from_argv).call(argv)

    assert_equal "/fix MASTER --dry-run --no-autofix --only=critique", message
  end

  def test_read_only_survives_even_with_apply
    argv = %w[/fix RAILS --READ-ONLY --apply]

    message = @host.initial_message_from_argv(argv)
    options = Master::CLI::CommandRegistry.send(:fix_dispatch_options, message.delete_prefix("/fix "), nil)

    assert_equal "RAILS", options.fetch(:target)
    assert_equal false, options.fetch(:apply)
  end

  def test_split_lane_and_intent_survive
    argv = %w[/fix --lane code RAILS BIZ --intent=content_only]

    assert_equal "/fix RAILS BIZ --lane code --intent=content_only", @host.initial_message_from_argv(argv)
  end

  def test_fix_flags_do_not_raise_an_option_error
    out, err = capture_io { @host.send(:initial_message_from_argv, ["/fix", "MASTER", "--max-files=3"]) }

    refute_match(/option error/, err + out)
  end

  # --model forces one model on every lane, as bin/cli's flag did before bin/master
  # absorbed it; the message the flag wraps is unchanged.
  def test_model_flag_forces_master_model
    previous = ENV.fetch("MASTER_MODEL", nil)
    ENV.delete("MASTER_MODEL")

    assert_equal "/status", @host.send(:initial_message_from_argv, ["--model", "x-ai/grok-4", "/status"])
    assert_equal "x-ai/grok-4", ENV.fetch("MASTER_MODEL")
  ensure
    previous.nil? ? ENV.delete("MASTER_MODEL") : ENV["MASTER_MODEL"] = previous
  end

  def test_spaced_only_flag_and_its_value_survive_together
    argv = ["/fix", "RAILS", "--only", "critique"]

    assert_equal "/fix RAILS --only critique", @host.initial_message_from_argv(argv)
  end

  def test_review_verbosity_flags_survive_without_option_errors
    argv = ["/fix", "MASTER", "--normal", "--quiet"]
    message = nil
    out, err = capture_io { message = @host.initial_message_from_argv(argv) }

    assert_equal "/fix MASTER --normal --quiet", message
    refute_match(/option error/, err + out)
  end

  def test_fix_lane_flag_survives_without_option_error
    argv = ["/fix", "MASTER", "--lane=visual"]
    message = nil
    out, err = capture_io { message = @host.initial_message_from_argv(argv) }

    assert_equal "/fix MASTER --lane=visual", message
    refute_match(/option error/, err + out)
  end

  def test_structural_recipe_value_and_mode_survive_into_the_message
    argv = ["/fix", "--recipe", "slugged_vertical_base", "--dry-run"]

    assert_equal "/fix --recipe slugged_vertical_base --dry-run",
                 @host.initial_message_from_argv(argv)
  end

  def test_structural_recipe_list_flag_survives_into_the_message
    argv = ["/fix", "--list-recipes"]

    assert_equal "/fix --list-recipes", @host.initial_message_from_argv(argv)
  end

  def test_structural_recipe_apply_flag_survives_into_the_message
    argv = ["/fix", "--recipe", "slugged_vertical_base", "--apply"]

    assert_equal "/fix --recipe slugged_vertical_base --apply",
                 @host.initial_message_from_argv(argv)
  end

  def test_other_unknown_flags_are_still_dropped
    assert_equal "/fix RAILS --autofix=off", @host.send(:initial_message_from_argv, ["/fix", "RAILS", "--bogus", "--autofix=off"])
  end
end
