# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/check_runner"
require "rbconfig"
require "tmpdir"
require "open3"

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
      assert_includes content, "command: #{RbConfig.ruby}"
      assert_includes content, "cwd: #{File.expand_path("../..", __dir__)}"
      assert_includes content, "exit=0"
      assert_includes content, "first output"
      assert_includes content, "first warning"
      assert_includes content, "=== failing check | FAIL |"
      assert_includes content, "exit=2"
      assert_includes content, "second output"
      assert_includes content, "second error"
      assert_equal 0o600, File.stat(log).mode & 0o777
      assert_equal 0o700, File.stat(File.dirname(log)).mode & 0o777
    end
  end

  def test_check_help_is_available_without_booting_master
    script = File.expand_path("../bin/check", __dir__)
    out, status = Open3.capture2e(RbConfig.ruby, script, "--help", chdir: File.expand_path("..", __dir__))

    assert status.success?, out
    assert_includes out, "Repair:"
    assert_includes out, "/fix [TREE]"
    assert_includes out, "bin/check is supplemental verification"
    assert_includes out, "bin/operator check is a separate"
  end

  def test_check_show_log_reads_a_bounded_tail_without_booting_master
    Dir.mktmpdir("check-log-cli") do |dir|
      log = File.join(dir, "latest.log")
      File.write(log, "one\ntwo\nthree\n")
      script = File.expand_path("../bin/check", __dir__)
      out, status = Open3.capture2e(
        { "MASTER_CHECK_RUN_LOG" => log },
        RbConfig.ruby, script, "--show-log", "--tail=2",
        chdir: File.expand_path("..", __dir__),
      )

      assert status.success?, out
      assert_includes out, "two\nthree\n"
      refute_includes out, "one\n"
      assert_includes out, log
    end
  end

  def test_check_show_log_refuses_missing_files_and_symlinks
    Dir.mktmpdir("check-log-cli") do |dir|
      script = File.expand_path("../bin/check", __dir__)
      env = { "MASTER_CHECK_RUN_LOG" => File.join(dir, "missing.log") }
      out, status = Open3.capture2e(env, RbConfig.ruby, script, "--show-log", chdir: File.expand_path("..", __dir__))
      refute status.success?
      assert_includes out, "No such file"

      target = File.join(dir, "target.log")
      File.write(target, "private\n")
      link = File.join(dir, "link.log")
      File.symlink(target, link)
      out, status = Open3.capture2e(
        { "MASTER_CHECK_RUN_LOG" => link },
        RbConfig.ruby, script, "--show-log",
        chdir: File.expand_path("..", __dir__),
      )
      refute status.success?
      assert_includes out, "symlinked"
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
