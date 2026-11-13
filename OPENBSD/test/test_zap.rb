# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

class ZapTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  ZAP = File.join(ROOT, "OPENBSD", "bin", "zap.rb")

  def run_zap(*args, stdin: "")
    Open3.capture2e(RbConfig.ruby, ZAP, *args, stdin_data: stdin)
  end

  def test_help_is_available_without_a_package
    output, status = run_zap("--help")

    assert status.success?, output
    assert_includes output, "usage: zap"
    assert_includes output, "Linux/Android use /proc"
  end

  def test_missing_pattern_is_rejected
    output, status = run_zap

    refute status.success?
    assert_includes output, "expected one search pattern"
  end

  def test_unmatched_pattern_is_a_clean_noop
    marker = "zap-no-process-#{Process.pid}-#{object_id}"
    output, status = run_zap(marker)

    assert status.success?, output
    assert_includes output, "no processes match"
  end

  def test_force_mode_signals_only_the_matching_process
    marker = "zap-worker-#{Process.pid}-#{object_id}"
    child = Process.spawn(RbConfig.ruby, "-e", "sleep 30 # #{marker}")

    output, status = run_zap("-f", "-s", "TERM", marker)

    assert status.success?, output
    assert_includes output, "sent SIGTERM to PID #{child}"
    Process.wait(child)
  ensure
    if child
      begin
        Process.kill("KILL", child)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(child)
      rescue Errno::ECHILD
        nil
      end
    end
  end

  def test_classic_signal_spelling_is_supported
    marker = "zap-worker-#{Process.pid}-#{object_id}"
    child = Process.spawn(RbConfig.ruby, "-e", "sleep 30 # #{marker}")

    output, status = run_zap("-TERM", "-f", marker)

    assert status.success?, output
    assert_includes output, "sent SIGTERM to PID #{child}"
    Process.wait(child)
  ensure
    if child
      begin
        Process.kill("KILL", child)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(child)
      rescue Errno::ECHILD
        nil
      end
    end
  end
end
