# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/check_runner"
require "rbconfig"
require "tmpdir"

class TestCheckRunnerStdin < Minitest::Test
  def test_timeout_preserves_partial_output_and_reports_failure
    runner = Operator::CheckRunner.new(
      prefix: "check-runner-timeout",
      root: File.expand_path("../..", __dir__),
      timeout: 0.1,
      quiet: true,
    )

    refute runner.run(
      "bounded timeout",
      RbConfig.ruby,
      "-e",
      "STDOUT.sync = true; puts 'started'; sleep 30",
    )

    output = runner.results.fetch(0).output
    assert_includes output, "started"
    assert_includes output, "step timed out after"
  end

  def test_combined_run_log_collects_passed_and_failed_step_output_privately
    Dir.mktmpdir("check-run-log") do |dir|
      log = File.join(dir, ".master", "check", "latest.log")
      runner = Operator::CheckRunner.new(
        prefix: "check-runner-log",
        root: File.expand_path("../..", __dir__),
        timeout: 5,
        quiet: true,
        log_path: log,
      )

      assert runner.run("passing check", RbConfig.ruby, "-e", "puts 'first output'; warn 'first warning'")
      refute runner.run("failing check", RbConfig.ruby, "-e", "puts 'second output'; warn 'second error'; exit 2")

      content = File.read(log)
      assert_includes content, "=== passing check | PASS |"
      assert_includes content, "first output"
      assert_includes content, "first warning"
      assert_includes content, "=== failing check | FAIL |"
      assert_includes content, "second output"
      assert_includes content, "second error"
      assert_equal 0o600, File.stat(log).mode & 0o777
      assert_equal 0o700, File.stat(File.dirname(log)).mode & 0o777
    end
  end

  def test_noninteractive_step_receives_eof
    runner = Operator::CheckRunner.new(
      prefix: "check-runner-test",
      root: File.expand_path("../..", __dir__),
      timeout: 2,
      quiet: true,
    )

    assert runner.run(
      "stdin eof",
      RbConfig.ruby,
      "-e",
      "exit(STDIN.read.empty? ? 0 : 1)",
    )
  end

  def test_step_does_not_inherit_the_booted_parent_group_selection
    previous = ENV["BUNDLE_WITHOUT"]
    ENV["BUNDLE_WITHOUT"] = "development:test"
    runner = Operator::CheckRunner.new(
      prefix: "check-runner-test",
      root: File.expand_path("../..", __dir__),
      timeout: 5,
      quiet: true,
    )

    assert runner.run(
      "group selection",
      RbConfig.ruby,
      "-e",
      'print(ENV["BUNDLE_WITHOUT"].inspect)',
    )
    assert_equal "nil", runner.results.fetch(0).output.strip
  ensure
    previous.nil? ? ENV.delete("BUNDLE_WITHOUT") : ENV["BUNDLE_WITHOUT"] = previous
  end
end
