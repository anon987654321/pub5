# frozen_string_literal: true

require_relative "test_helper"

# bin/master is a script, so the two argv helpers are evaluated from its source
# rather than booting the runtime.
class TestCliCommandFlags < Minitest::Test
  SOURCE = File.read(File.expand_path("../bin/master", __dir__))
  HELPERS = SOURCE[/^COMMAND_FLAG.*?(?=^# Flags are read before the runtime boots)/m]

  def setup
    host = Object.new
    host.extend(Module.new { def self.status(*, **) = nil })
    host.instance_eval("require 'optparse'; module Master; module Trace; module Dmesg; def self.status(*, **) = nil; end; end; end\n#{HELPERS}", __FILE__, 1)
    @host = host
  end

  def test_fix_flags_survive_into_the_message
    argv = ["/fix", "rails", "--max-files=25", "--autofix=on"]

    assert_equal "/fix rails --max-files=25 --autofix=on", @host.send(:initial_message_from_argv, argv)
  end

  def test_no_critique_survives_into_the_message_without_an_option_error
    argv = ["/fix", "master", "--no-critique"]
    message = nil
    out, err = capture_io { message = @host.method(:initial_message_from_argv).call(argv) }

    assert_equal "/fix master --no-critique", message

    refute_match(/option error/, err + out)
  end

  def test_blockers_survives_into_the_message
    assert_equal "/fix rails --blockers", @host.initial_message_from_argv(["/fix", "rails", "--blockers"])
  end

  def test_dry_run_is_never_dropped
    argv = ["/fix", "master", "--dry-run", "--no-autofix", "--only=critique"]

    message = @host.method(:initial_message_from_argv).call(argv)

    assert_equal "/fix master --dry-run --no-autofix --only=critique", message
  end

  def test_fix_flags_do_not_raise_an_option_error
    out, err = capture_io { @host.send(:initial_message_from_argv, ["/fix", "master", "--max-files=3"]) }

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
    argv = ["/fix", "rails", "--only", "critique"]

    assert_equal "/fix rails --only critique", @host.initial_message_from_argv(argv)
  end

  def test_review_verbosity_flags_survive_without_option_errors
    argv = ["/fix", "master", "--normal", "--quiet"]
    message = nil
    out, err = capture_io { message = @host.initial_message_from_argv(argv) }

    assert_equal "/fix master --normal --quiet", message
    refute_match(/option error/, err + out)
  end

  def test_fix_lane_flag_survives_without_option_error
    argv = ["/fix", "master", "--lane=visual"]
    message = nil
    out, err = capture_io { message = @host.initial_message_from_argv(argv) }

    assert_equal "/fix master --lane=visual", message
    refute_match(/option error/, err + out)
  end

  def test_other_unknown_flags_are_still_dropped
    assert_equal "/fix rails --autofix=off", @host.send(:initial_message_from_argv, ["/fix", "rails", "--bogus", "--autofix=off"])
  end
end
